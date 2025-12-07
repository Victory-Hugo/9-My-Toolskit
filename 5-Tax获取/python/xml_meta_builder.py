#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
根据本地BioSample XML与assembly_biosample_map.csv生成最终的分类元数据表。
"""

from __future__ import annotations

import argparse
import csv
import logging
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional
import xml.etree.ElementTree as ET

from taxonomy_utils import build_lineage, load_names, load_nodes


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="从BioSample XML构建final_meta.csv")
    parser.add_argument("--meta-dir", required=True, type=Path, help="包含BioSample XML的目录")
    parser.add_argument("--map-csv", required=True, type=Path, help="assembly_biosample_map.csv路径")
    parser.add_argument("--names-dmp", required=True, type=Path, help="NCBI names.dmp路径")
    parser.add_argument("--nodes-dmp", required=True, type=Path, help="NCBI nodes.dmp路径")
    parser.add_argument("--output", required=True, type=Path, help="输出的final_meta.csv路径")
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="日志等级 (default: INFO)",
    )
    return parser.parse_args()


def read_mapping(map_path: Path) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    with map_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            standard_id = (row.get("Standard_ID") or "").strip()
            input_id = (row.get("Input_ID") or "").strip()
            biosample = (row.get("BioSample") or "").strip()
            if not biosample or not (standard_id or input_id):
                continue
            assembly = standard_id or input_id
            rows.append({"Assembly": assembly, "BioSample": biosample})
    return rows


def extract_taxid_from_xml(xml_path: Path) -> Optional[str]:
    """使用iterparse快速提取taxonomy_id，若不存在则返回None。"""
    try:
        for _event, elem in ET.iterparse(xml_path, events=("start",)):
            if elem.tag.endswith("Organism"):
                taxid = elem.attrib.get("taxonomy_id")
                if taxid:
                    return taxid.strip()
    except ET.ParseError as exc:
        logging.warning("解析失败 %s: %s", xml_path, exc)
    return None


def resolve_rank_name(
    taxid: str,
    nodes: Dict[str, tuple[str, str]],
    names: Dict[str, str],
    targets: List[str],
) -> str:
    """
    沿节点向上寻找目标rank名称，用于兼容domain/superkingdom等差异。
    """
    current = taxid
    visited = set()
    found: Dict[str, str] = {}
    while current and current not in visited:
        visited.add(current)
        parent, rank = nodes.get(current, ("", ""))
        if rank in targets:
            name = names.get(current, "")
            if name and rank not in found:
                found[rank] = name
        if not parent or parent == current:
            break
        current = parent
    for rank in targets:
        if rank in found:
            return found[rank]
    return ""


def domain_name(taxid: str, lineage: Dict[str, str], nodes: Dict[str, tuple[str, str]], names: Dict[str, str]) -> str:
    # superkingdom优先，其次domain/kingdom
    return lineage.get("superkingdom") or resolve_rank_name(taxid, nodes, names, ["superkingdom", "domain", "kingdom"]) or ""


def build_rows(
    mapping: Iterable[Dict[str, str]],
    meta_dir: Path,
    *,
    names: Dict[str, str],
    nodes: Dict[str, tuple[str, str]],
) -> List[Dict[str, str]]:
    results: List[Dict[str, str]] = []
    for item in mapping:
        assembly = item["Assembly"]
        biosample = item["BioSample"]
        xml_path = meta_dir / f"{biosample}.xml"
        taxid = ""
        lineage = {
            "superkingdom": "",
            "kingdom": "",
            "phylum": "",
            "class": "",
            "order": "",
            "family": "",
            "genus": "",
            "species": "",
        }

        if not xml_path.exists():
            logging.warning("缺少XML: %s", xml_path)
        else:
            parsed_taxid = extract_taxid_from_xml(xml_path)
            if parsed_taxid:
                taxid = parsed_taxid
                lineage, _sci = build_lineage(taxid, nodes=nodes, names=names)
            else:
                logging.warning("未在XML中找到taxonomy_id: %s", xml_path)

        results.append(
            {
                "Assembly": assembly,
                "BioSample": biosample,
                "TaxID": taxid,
                "Domain": domain_name(taxid, lineage, nodes, names) if taxid else "",
                "Phylum": lineage.get("phylum", ""),
                "Class": lineage.get("class", ""),
                "Order": lineage.get("order", ""),
                "Family": lineage.get("family", ""),
                "Genus": lineage.get("genus", ""),
                "Species": lineage.get("species", ""),
            }
        )
    return results


def write_output(rows: List[Dict[str, str]], output: Path) -> None:
    fieldnames = [
        "Assembly",
        "BioSample",
        "TaxID",
        "Domain",
        "Phylum",
        "Class",
        "Order",
        "Family",
        "Genus",
        "Species",
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    args = parse_args()
    logging.basicConfig(level=getattr(logging, args.log_level), format="%(asctime)s %(levelname)s: %(message)s")

    mapping = read_mapping(args.map_csv)
    if not mapping:
        logging.error("未能从映射文件中读取到有效数据: %s", args.map_csv)
        return 1

    names = load_names(args.names_dmp)
    nodes = load_nodes(args.nodes_dmp)

    rows = build_rows(mapping, args.meta_dir, names=names, nodes=nodes)
    write_output(rows, args.output)
    logging.info("完成输出: %s (%d rows)", args.output, len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
