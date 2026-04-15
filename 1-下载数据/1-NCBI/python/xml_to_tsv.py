#!/usr/bin/env python3
"""
xml_to_tsv.py — 将目录下所有 XML 文件提取为单一 TSV 文件

功能：
  - 递归扁平化 XML 树结构为键值对
  - 自动处理 NCBI BioSample / SRA 等格式的区分性属性（attribute_name、db 等）
  - 两遍处理：先并行解析全部文件收集所有字段名，再统一写出 TSV
  - 相同路径字段合并为同一列，同文件内重复 key 添加 _2、_3 后缀

用法（命令行）：
  python xml_to_tsv.py --input-dir /path/to/xmls --output-tsv result.tsv
  python xml_to_tsv.py --input-dir /path/to/xmls --output-tsv result.tsv --jobs 8 --verbose

用法（模块导入）：
  import xml_to_tsv
  xml_to_tsv.run(input_dir="/path/to/xmls", output_tsv="result.tsv", jobs=4)
"""

import argparse
import csv
import logging
import sys
import xml.etree.ElementTree as ET
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Dict, List, Tuple

log = logging.getLogger(__name__)

# 用于生成区分性 key 后缀的属性名（按优先级排列）
_DISTINGUISHING_ATTRS: Tuple[str, ...] = (
    "attribute_name",
    "harmonized_name",
    "db",
    "type",
    "name",
)
_SKIP_AS_SUFFIX = set(_DISTINGUISHING_ATTRS)


def _flatten_element(element: ET.Element, path: str = "") -> List[Tuple[str, str]]:
    """
    递归扁平化单个 XML 元素，返回 (key, value) 列表。

    key 命名规则：
      - 普通元素：   parent.tag
      - 带区分性属性：parent.tag[attribute_value]
      - 元素属性：   parent.tag@attr_name
      - 含文本的父节点：parent.tag._text
    """
    tag = element.tag.split("}")[-1] if "}" in element.tag else element.tag

    # 查找第一个有效的区分性属性作为 key 后缀
    suffix = None
    for attr in _DISTINGUISHING_ATTRS:
        val = element.get(attr)
        if val:
            suffix = val.replace(" ", "_").replace("/", "_").replace("\\", "_")
            break

    if suffix:
        node_key = f"{path}.{tag}[{suffix}]" if path else f"{tag}[{suffix}]"
    else:
        node_key = f"{path}.{tag}" if path else tag

    results: List[Tuple[str, str]] = []

    # 提取元素属性（排除已用作后缀的属性）
    for attr_name, attr_val in element.attrib.items():
        if attr_name not in _SKIP_AS_SUFFIX:
            results.append((f"{node_key}@{attr_name}", attr_val))

    children = list(element)
    text = (element.text or "").strip()

    if children:
        if text:
            results.append((f"{node_key}._text", text))
        for child in children:
            results.extend(_flatten_element(child, node_key))
    elif text:
        results.append((node_key, text))

    return results


def extract_record(xml_path: str) -> Dict[str, str]:
    """
    解析单个 XML 文件，返回扁平化字段字典。

    字典第一项固定为 __source_file__（来源文件路径）。
    同一文件内重复 key 自动添加 _2、_3 等后缀。

    解析失败时返回含 __parse_error__ 字段的字典（不抛出异常）。
    """
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        pairs = _flatten_element(root)
    except ET.ParseError as exc:
        log.warning("XML 解析失败 %s: %s", xml_path, exc)
        return {
            "__source_file__": str(xml_path),
            "__parse_error__": str(exc),
        }

    record: Dict[str, str] = {"__source_file__": str(xml_path)}
    key_seen: Dict[str, int] = {}

    for key, val in pairs:
        if key in record:
            n = key_seen.get(key, 1) + 1
            key_seen[key] = n
            record[f"{key}_{n}"] = val
        else:
            record[key] = val

    return record


def run(
    input_dir: str,
    output_tsv: str,
    jobs: int = 4,
    verbose: bool = False,
) -> int:
    """
    处理 input_dir 下所有 XML 文件，输出统一 TSV 文件。

    两遍处理：
      1. 并行解析全部 XML，收集所有可能的字段名
      2. 以统一表头写出 TSV，缺失字段留空

    Args:
        input_dir:  包含 XML 文件的目录路径（递归搜索 *.xml）
        output_tsv: 输出 TSV 文件路径（父目录不存在时自动创建）
        jobs:       并行进程数（默认 4）
        verbose:    是否开启 DEBUG 日志（默认 False）

    Returns:
        0 表示成功，非 0 表示失败
    """
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%H:%M:%S",
    )

    input_path = Path(input_dir)
    if not input_path.is_dir():
        log.error("输入路径不存在或不是目录: %s", input_dir)
        return 1

    xml_files = sorted(input_path.rglob("*.xml"))
    if not xml_files:
        log.error("在 %s 中未找到任何 .xml 文件", input_dir)
        return 1

    log.info("发现 %d 个 XML 文件，并行进程数: %d", len(xml_files), jobs)

    # ── 第一遍：并行解析所有 XML ──────────────────────────────────────
    records: List[Dict[str, str]] = [None] * len(xml_files)  # 预分配保持顺序
    all_keys: set = set()
    index_map: Dict = {}

    with ProcessPoolExecutor(max_workers=jobs) as executor:
        future_map = {
            executor.submit(extract_record, str(f)): idx
            for idx, f in enumerate(xml_files)
        }
        done = 0
        for future in as_completed(future_map):
            idx = future_map[future]
            done += 1
            try:
                record = future.result()
            except Exception as exc:
                log.warning("处理 %s 时异常: %s", xml_files[idx], exc)
                record = {
                    "__source_file__": str(xml_files[idx]),
                    "__parse_error__": str(exc),
                }
            records[idx] = record
            all_keys.update(record.keys())

            if done % 500 == 0 or done == len(xml_files):
                log.info("解析进度: %d / %d", done, len(xml_files))

    valid_records = [r for r in records if r is not None]
    if not valid_records:
        log.error("没有成功解析任何文件")
        return 1

    # ── 构建统一表头（__source_file__ 置首，其余按字母排序）────────────
    all_keys.discard("__source_file__")
    sorted_keys = ["__source_file__"] + sorted(all_keys)
    log.info("共提取 %d 个字段（列）", len(sorted_keys))

    # ── 第二遍：写出 TSV ──────────────────────────────────────────────
    output_path = Path(output_tsv)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=sorted_keys,
            delimiter="\t",
            extrasaction="ignore",
            restval="",
        )
        writer.writeheader()
        for record in valid_records:
            writer.writerow(record)

    log.info(
        "TSV 已写入: %s  （%d 行 × %d 列）",
        output_tsv,
        len(valid_records),
        len(sorted_keys),
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="将目录下所有 XML 文件提取为单一 TSV 文件",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python xml_to_tsv.py --input-dir /data/biosample_xml --output-tsv result.tsv
  python xml_to_tsv.py --input-dir /data/biosample_xml --output-tsv result.tsv --jobs 8 --verbose
        """,
    )
    parser.add_argument(
        "--input-dir",
        required=True,
        metavar="DIR",
        help="包含 XML 文件的输入目录（递归搜索 *.xml）",
    )
    parser.add_argument(
        "--output-tsv",
        required=True,
        metavar="FILE",
        help="输出 TSV 文件路径",
    )
    parser.add_argument(
        "--jobs", "-j",
        type=int,
        default=4,
        metavar="N",
        help="并行进程数（默认: 4）",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="显示 DEBUG 日志",
    )
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    return run(
        input_dir=args.input_dir,
        output_tsv=args.output_tsv,
        jobs=args.jobs,
        verbose=args.verbose,
    )


if __name__ == "__main__":
    raise SystemExit(main())
