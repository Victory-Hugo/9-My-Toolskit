#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
本地taxonomy数据读取与谱系构建工具。
"""

from __future__ import annotations

import csv
import logging
import os
import pickle
from pathlib import Path
from typing import Dict, List, Optional, Tuple

RANK_ORDER = ["superkingdom", "kingdom", "phylum", "class", "order", "family", "genus", "species"]


def read_accessions(accession_file: Path) -> List[str]:
    """读取Accession列表，过滤空行与注释行。"""
    accessions: List[str] = []
    with accession_file.open("r", encoding="utf-8") as handle:
        for line in handle:
            cleaned = line.strip()
            if not cleaned or cleaned.startswith("#"):
                continue
            accessions.append(cleaned)
    return accessions


def _load_cache(cache_path: Path, src_mtime: float) -> Optional[Dict[str, str]]:
    """尝试读取缓存，校验mtime。"""
    if cache_path.exists():
        try:
            with cache_path.open("rb") as handle:
                payload = pickle.load(handle)
            if payload.get("mtime") == src_mtime:
                logging.info("使用缓存: %s", cache_path)
                return payload.get("data")
        except Exception:
            pass
    return None


def _save_cache(cache_path: Path, src_mtime: float, data: Dict) -> None:
    """保存缓存。"""
    try:
        with cache_path.open("wb") as handle:
            pickle.dump({"mtime": src_mtime, "data": data}, handle, protocol=pickle.HIGHEST_PROTOCOL)
        logging.info("写入缓存: %s", cache_path)
    except Exception:
        logging.warning("缓存写入失败: %s", cache_path)


def load_names(names_dmp: Path) -> Dict[str, str]:
    """载入names.dmp，提取scientific name映射，带缓存。"""
    mtime = names_dmp.stat().st_mtime
    cache_path = names_dmp.with_suffix(names_dmp.suffix + ".pkl")
    cached = _load_cache(cache_path, mtime)
    if cached is not None:
        return cached

    names: Dict[str, str] = {}
    with names_dmp.open("r", encoding="utf-8") as handle:
        for raw in handle:
            parts = [p.strip() for p in raw.split("|")]
            if len(parts) < 4:
                continue
            tax_id, name_txt, _unique_name, name_class = parts[:4]
            if name_class == "scientific name" and tax_id:
                names[tax_id] = name_txt

    _save_cache(cache_path, mtime, names)
    return names


def load_nodes(nodes_dmp: Path) -> Dict[str, Tuple[str, str]]:
    """载入nodes.dmp，生成tax_id到(父节点, rank)的映射，带缓存。"""
    mtime = nodes_dmp.stat().st_mtime
    cache_path = nodes_dmp.with_suffix(nodes_dmp.suffix + ".pkl")
    cached = _load_cache(cache_path, mtime)
    if cached is not None:
        return cached

    nodes: Dict[str, Tuple[str, str]] = {}
    with nodes_dmp.open("r", encoding="utf-8") as handle:
        for raw in handle:
            parts = [p.strip() for p in raw.split("|")]
            if len(parts) < 3:
                continue
            tax_id, parent_id, rank = parts[:3]
            nodes[tax_id] = (parent_id, rank)

    _save_cache(cache_path, mtime, nodes)
    return nodes


def build_lineage(
    taxid: str,
    *,
    nodes: Dict[str, Tuple[str, str]],
    names: Dict[str, str],
) -> Tuple[Dict[str, str], str]:
    """根据nodes与names构建指定rank的分类层级，返回(层级字典, 该taxid的学名)。"""
    lineage = {rank: "" for rank in RANK_ORDER}
    sci_name = names.get(taxid, "")
    current = taxid
    visited = set()

    while current and current not in visited:
        visited.add(current)
        parent, rank = nodes.get(current, ("", ""))
        current_name = names.get(current, "")
        if rank in lineage and not lineage[rank]:
            lineage[rank] = current_name
        if not parent or parent == current:
            break
        current = parent

    return lineage, sci_name


def write_results(
    rows: List[Dict[str, str]],
    output_file: Path,
) -> None:
    """写出结果CSV。"""
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
        for row in rows:
            writer.writerow(row)
