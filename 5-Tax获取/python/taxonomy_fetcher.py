#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
使用NCBI E-utilities将Accession ID转换为Taxonomy ID，并基于本地NCBI分类数据库生成完整分类信息。
支持命令行与import两种使用方式。
"""

from __future__ import annotations

import argparse
import logging
import csv
from pathlib import Path
from typing import Dict, List, Optional

from network_fetcher import fetch_taxid_via_entrez
from taxonomy_utils import (
    RANK_ORDER,
    build_lineage,
    load_names,
    load_nodes,
    read_accessions,
    write_results,
)


def run(
    accession_file: Path,
    names_dmp: Path,
    nodes_dmp: Path,
    output_file: Path,
    *,
    email: Optional[str] = None,
    api_key: Optional[str] = None,
    delay: float = 0.34,
    db_priority: Optional[List[str]] = None,
) -> Path:
    """
    主执行逻辑：读取Accession，获取TaxID，组装分类信息，并输出CSV。
    返回输出文件路径。采用流式写入以支持大规模数据。
    """
    logging.info("Loading taxonomy database ...")
    names = load_names(names_dmp)
    nodes = load_nodes(nodes_dmp)
    priority = db_priority or ["nuccore", "assembly", "protein"]

    accessions = read_accessions(accession_file)
    output_file.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "Accession",
        "TaxID",
        "Superkingdom",
        "Kingdom",
        "Phylum",
        "Class",
        "Order",
        "Family",
        "Genus",
        "Species",
        "ScientificName",
        "DB",
        "Status",
        "Message",
    ]

    with output_file.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for accession in accessions:
            taxid = ""
            db_used: Optional[str] = None
            status = "FAILED"
            message = ""
            try:
                taxid, db_used, message = fetch_taxid_via_entrez(
                    accession,
                    email=email,
                    api_key=api_key,
                    db_priority=priority,
                    delay=delay,
                )
                if taxid is None:
                    status = "FAILED"
                else:
                    status = "OK"
            except Exception as exc:  # noqa: BLE001
                message = f"Exception: {exc}"
                status = "FAILED"

            lineage = {rank: "" for rank in RANK_ORDER}
            sci_name = ""
            if taxid and status == "OK":
                lineage, sci_name = build_lineage(taxid, nodes=nodes, names=names)

            row = {
                "Accession": accession,
                "TaxID": taxid or "",
                "Superkingdom": lineage.get("superkingdom", ""),
                "Kingdom": lineage.get("kingdom", ""),
                "Phylum": lineage.get("phylum", ""),
                "Class": lineage.get("class", ""),
                "Order": lineage.get("order", ""),
                "Family": lineage.get("family", ""),
                "Genus": lineage.get("genus", ""),
                "Species": lineage.get("species", ""),
                "ScientificName": sci_name,
                "DB": db_used or "",
                "Status": status,
                "Message": message,
            }
            writer.writerow(row)
            handle.flush()
            logging.info("写入分类信息：%s | TaxID=%s | status=%s | db=%s", accession, row["TaxID"], status, db_used or "")

    return output_file


def build_arg_parser() -> argparse.ArgumentParser:
    """构建命令行参数解析。"""
    parser = argparse.ArgumentParser(
        description="根据Accession ID获取TaxID并输出完整分类信息",
    )
    parser.add_argument(
        "--accession-file",
        required=True,
        type=Path,
        help="包含Accession ID的输入文件，每行一个",
    )
    parser.add_argument(
        "--names-dmp",
        required=True,
        type=Path,
        help="NCBI names.dmp 文件路径",
    )
    parser.add_argument(
        "--nodes-dmp",
        required=True,
        type=Path,
        help="NCBI nodes.dmp 文件路径",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="输出CSV文件路径",
    )
    parser.add_argument(
        "--email",
        default=None,
        help="提交给NCBI的email",
    )
    parser.add_argument(
        "--api-key",
        default=None,
        dest="api_key",
        help="NCBI API Key（可选）",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.34,
        help="请求间隔秒数，遵循NCBI限速",
    )
    parser.add_argument(
        "--db-priority",
        nargs="+",
        default=["nuccore", "assembly", "protein"],
        help="E-utilities查询数据库优先级",
    )
    return parser


def main() -> None:
    """命令行入口。"""
    parser = build_arg_parser()
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")
    run(
        accession_file=args.accession_file,
        names_dmp=args.names_dmp,
        nodes_dmp=args.nodes_dmp,
        output_file=args.output,
        email=args.email,
        api_key=args.api_key,
        delay=args.delay,
        db_priority=args.db_priority,
    )


if __name__ == "__main__":
    main()
