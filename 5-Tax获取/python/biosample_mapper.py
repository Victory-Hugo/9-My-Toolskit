#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从任意NCBI accession映射到BioSample ID的工具。
支持命令行与import双模式。
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import re
import time
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Tuple
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen

from taxonomy_utils import read_accessions

EUTILS_BASE = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"

# 正则判断类型
RE_SRA_RUN = re.compile(r"^SRR\d+$", re.IGNORECASE)
RE_SRA_EXP = re.compile(r"^SRX\d+$", re.IGNORECASE)
RE_SRA_PROJ = re.compile(r"^SRP\d+$", re.IGNORECASE)
RE_SRA_SAMPLE = re.compile(r"^SRS\d+$", re.IGNORECASE)
RE_BIOSAMPLE = re.compile(r"^SAM[END]\d+$", re.IGNORECASE)
RE_ASM = re.compile(r"^GC[AF]_\d+", re.IGNORECASE)
RE_GEO_GSM = re.compile(r"^GSM\d+$", re.IGNORECASE)
RE_GEO_GSE = re.compile(r"^GSE\d+$", re.IGNORECASE)
RE_BIOPROJECT = re.compile(r"^PRJ[A-Z]{2}\d+", re.IGNORECASE)
RE_NUCCORE = re.compile(r"^(NC_|NM_|XM_|XP_|WP_|NZ_|[A-Z]{2}\d{6,}|[A-Z]{4}\d{2})", re.IGNORECASE)


def eutils_request(db: str, params: Dict[str, str], *, email: Optional[str], api_key: Optional[str]) -> Dict:
    """GET请求E-utilities并返回JSON。"""
    query_params = dict(params)
    if email:
        query_params["email"] = email
    if api_key:
        query_params["api_key"] = api_key
    url = f"{EUTILS_BASE}/{params.pop('endpoint')}?{urlencode(query_params)}"
    with urlopen(url) as response:
        return json.loads(response.read().decode("utf-8"))


def esearch_ids(db: str, term: str, *, email: Optional[str], api_key: Optional[str]) -> List[str]:
    """esearch返回id列表。"""
    params = {
        "endpoint": "esearch.fcgi",
        "db": db,
        "term": term,
        "retmode": "json",
        "retmax": "5",
    }
    try:
        data = eutils_request(db, params, email=email, api_key=api_key)
        return data.get("esearchresult", {}).get("idlist", [])
    except Exception:
        return []


def esummary_item(db: str, uid: str, *, email: Optional[str], api_key: Optional[str]) -> Dict:
    """esummary返回指定uid的结果块。"""
    params = {"endpoint": "esummary.fcgi", "db": db, "id": uid, "retmode": "json"}
    try:
        data = eutils_request(db, params, email=email, api_key=api_key)
        return data.get("result", {}).get(uid, {})  # type: ignore[return-value]
    except Exception:
        return {}


def efetch_gb(accession: str, *, email: Optional[str], api_key: Optional[str]) -> str:
    """efetch GenBank文本。"""
    params = {
        "db": "nuccore",
        "id": accession,
        "rettype": "gb",
        "retmode": "text",
    }
    query = urlencode({k: v for k, v in params.items() if v})
    url = f"{EUTILS_BASE}/efetch.fcgi?{query}"
    try:
        with urlopen(url) as response:
            return response.read().decode("utf-8", errors="ignore")
    except Exception:
        return ""


def detect_type(acc: str) -> str:
    """识别accession类型，返回类型标签。"""
    if RE_BIOSAMPLE.match(acc):
        return "biosample"
    if RE_SRA_RUN.match(acc):
        return "sra_run"
    if RE_SRA_EXP.match(acc):
        return "sra_exp"
    if RE_SRA_PROJ.match(acc):
        return "sra_proj"
    if RE_SRA_SAMPLE.match(acc):
        return "sra_sample"
    if RE_ASM.match(acc):
        return "assembly"
    if RE_GEO_GSM.match(acc):
        return "gsm"
    if RE_GEO_GSE.match(acc):
        return "gse"
    if RE_BIOPROJECT.match(acc):
        return "bioproject"
    if RE_NUCCORE.match(acc):
        return "nuccore"
    return "unknown"


def parse_biosample_from_expxml(expxml: str) -> Optional[str]:
    """从SRA expxml中解析BioSample。"""
    match = re.search(r'BioSample accession="(SAM[END]\d+)"', expxml)
    if match:
        return match.group(1)
    match = re.search(r'bio[sS]ample[^A-Za-z0-9]+(SAM[END]\d+)', expxml)
    if match:
        return match.group(1)
    return None


def handle_sra(acc: str, *, email: Optional[str], api_key: Optional[str], delay: float) -> Optional[str]:
    """处理SRR/SRX/SRP/SRS，返回BioSample ID。"""
    # 先尝试runinfo直接解析BioSample
    runinfo_url = f"{EUTILS_BASE}/efetch.fcgi?db=sra&id={acc}&rettype=runinfo&retmode=text"
    try:
        with urlopen(runinfo_url) as response:
            text = response.read().decode("utf-8", errors="ignore")
        lines = [l for l in text.splitlines() if l.strip()]
        if len(lines) >= 2:
            header = lines[0].split(",")
            biosample_idx = header.index("BioSample") if "BioSample" in header else -1
            if biosample_idx >= 0:
                biosample_val = lines[1].split(",")[biosample_idx].strip()
                if biosample_val:
                    time.sleep(delay)
                    return biosample_val
    except Exception:
        pass

    ids = esearch_ids("sra", f"{acc}[Accession]", email=email, api_key=api_key)
    if not ids:
        time.sleep(delay)
        return None
    item = esummary_item("sra", ids[0], email=email, api_key=api_key)
    expxml = item.get("expxml", "")
    biosample = parse_biosample_from_expxml(expxml)
    time.sleep(delay)
    return biosample


def handle_assembly(acc: str, *, email: Optional[str], api_key: Optional[str], delay: float) -> Optional[str]:
    """处理GCA/GCF，返回BioSample ID。"""
    ids = esearch_ids("assembly", f"{acc}[Assembly Accession]", email=email, api_key=api_key)
    if not ids:
        time.sleep(delay)
        return None
    item = esummary_item("assembly", ids[0], email=email, api_key=api_key)
    biosample = item.get("biosampleaccn") or item.get("BioSampleAccn")
    time.sleep(delay)
    return biosample


def handle_nuccore(acc: str, *, email: Optional[str], api_key: Optional[str], delay: float) -> Optional[str]:
    """处理nuccore/蛋白序列，尝试从esummary或gb注释获取BioSample。"""
    ids = esearch_ids("nuccore", f"{acc}[Accession]", email=email, api_key=api_key)
    biosample: Optional[str] = None
    if ids:
        item = esummary_item("nuccore", ids[0], email=email, api_key=api_key)
        biosample = item.get("biosample") or item.get("BioSample")
    if not biosample:
        gb_text = efetch_gb(acc, email=email, api_key=api_key)
        match = re.search(r"/biosample=\"(SAM[END]\d+)\"", gb_text, re.IGNORECASE)
        if match:
            biosample = match.group(1)
    time.sleep(delay)
    return biosample


def handle_gsm(acc: str, *, email: Optional[str], api_key: Optional[str], delay: float) -> Optional[str]:
    """简化处理GSM：通过GDS esummary尝试捕获SRA链接中的BioSample。"""
    ids = esearch_ids("gds", f"{acc}[Accession]", email=email, api_key=api_key)
    if not ids:
        time.sleep(delay)
        return None
    item = esummary_item("gds", ids[0], email=email, api_key=api_key)
    # extrelations/ssrna可能包含SRA编号，尝试再次走SRA解析
    ext = json.dumps(item)
    sra_match = re.search(r"(SRR\\d+|SRX\\d+|SRS\\d+|SRP\\d+)", ext)
    if sra_match:
        biosample = handle_sra(sra_match.group(1), email=email, api_key=api_key, delay=delay)
        time.sleep(delay)
        return biosample
    time.sleep(delay)
    return None


def handle_gse(acc: str, *, email: Optional[str], api_key: Optional[str], delay: float) -> Optional[str]:
    """简化处理GSE：优先找GSM后跳转。"""
    ids = esearch_ids("gds", f"{acc}[Accession]", email=email, api_key=api_key)
    if not ids:
        time.sleep(delay)
        return None
    item = esummary_item("gds", ids[0], email=email, api_key=api_key)
    subsetinfo = json.dumps(item)
    gsm_match = re.findall(r"GSM\\d+", subsetinfo)
    for gsm in gsm_match:
        biosample = handle_gsm(gsm, email=email, api_key=api_key, delay=delay)
        if biosample:
            time.sleep(delay)
            return biosample
    time.sleep(delay)
    return None


def handle_biosample(acc: str, *, email: Optional[str], api_key: Optional[str], delay: float) -> Optional[str]:
    """直接BioSample编号。"""
    time.sleep(delay)
    return acc


def handle_unknown(acc: str, *, email: Optional[str], api_key: Optional[str], delay: float) -> Optional[str]:
    """未知类型，返回None。"""
    time.sleep(delay)
    return None


HANDLERS: Dict[str, Callable[[str], Optional[str]]] = {}


def _init_handlers(email: Optional[str], api_key: Optional[str], delay: float) -> Dict[str, Callable[[str], Optional[str]]]:
    """生成带闭包配置的handler字典。"""
    return {
        "sra_run": lambda acc: handle_sra(acc, email=email, api_key=api_key, delay=delay),
        "sra_exp": lambda acc: handle_sra(acc, email=email, api_key=api_key, delay=delay),
        "sra_proj": lambda acc: handle_sra(acc, email=email, api_key=api_key, delay=delay),
        "sra_sample": lambda acc: handle_sra(acc, email=email, api_key=api_key, delay=delay),
        "assembly": lambda acc: handle_assembly(acc, email=email, api_key=api_key, delay=delay),
        "nuccore": lambda acc: handle_nuccore(acc, email=email, api_key=api_key, delay=delay),
        "gsm": lambda acc: handle_gsm(acc, email=email, api_key=api_key, delay=delay),
        "gse": lambda acc: handle_gse(acc, email=email, api_key=api_key, delay=delay),
        "biosample": lambda acc: handle_biosample(acc, email=email, api_key=api_key, delay=delay),
        "bioproject": lambda acc: handle_unknown(acc, email=email, api_key=api_key, delay=delay),
        "unknown": lambda acc: handle_unknown(acc, email=email, api_key=api_key, delay=delay),
    }


def map_biosample_stream(
    accessions: Iterable[str],
    *,
    email: Optional[str],
    api_key: Optional[str],
    delay: float,
    writer: csv.writer,
    handle,
) -> None:
    """核心映射逻辑，流式写出 (acc, biosample or NA)。"""
    handlers = _init_handlers(email, api_key, delay)
    for acc in accessions:
        acc = acc.strip()
        if not acc:
            continue
        acc_type = detect_type(acc)
        handler = handlers.get(acc_type, handlers["unknown"])
        biosample = None
        try:
            biosample = handler(acc)
        except Exception as exc:  # noqa: BLE001
            logging.warning("处理 %s 时出错: %s", acc, exc)
        out_val = biosample or "NA"
        writer.writerow([acc, out_val])
        handle.flush()
        logging.info("写入BioSample映射：%s -> %s", acc, out_val)


def run(
    accession_file: Path,
    output_file: Path,
    *,
    email: Optional[str] = None,
    api_key: Optional[str] = None,
    delay: float = 0.34,
) -> Path:
    """主流程：读取accession，映射BioSample，输出CSV。"""
    accessions = read_accessions(accession_file)
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with output_file.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["Accession", "BioSample"])
        map_biosample_stream(
            accessions,
            email=email,
            api_key=api_key,
            delay=delay,
            writer=writer,
            handle=handle,
        )
    return output_file


def build_arg_parser() -> argparse.ArgumentParser:
    """构建命令行参数。"""
    parser = argparse.ArgumentParser(description="将任意NCBI accession映射到BioSample ID并输出CSV")
    parser.add_argument("--accession-file", required=True, type=Path, help="包含accession的输入文件")
    parser.add_argument("--output", required=True, type=Path, help="输出CSV文件路径")
    parser.add_argument("--email", default=None, help="提交给NCBI的email")
    parser.add_argument("--api-key", dest="api_key", default=None, help="NCBI API Key（可选）")
    parser.add_argument("--delay", type=float, default=0.34, help="请求间隔秒数")
    return parser


def main() -> None:
    parser = build_arg_parser()
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")
    run(
        accession_file=args.accession_file,
        output_file=args.output,
        email=args.email,
        api_key=args.api_key,
        delay=args.delay,
    )


if __name__ == "__main__":
    main()
