#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
基于NCBI E-utilities的网络查询模块：将Accession转换为TaxID。
"""

from __future__ import annotations

import json
import time
import re
from typing import Iterable, Optional, Tuple
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen

EUTILS_BASE = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"


def fetch_taxid_via_entrez(
    accession: str,
    *,
    email: Optional[str],
    api_key: Optional[str],
    db_priority: Iterable[str],
    delay: float,
) -> Tuple[Optional[str], Optional[str], str]:
    """
    调用E-utilities将Accession转换为TaxID。
    返回(taxid, 使用的数据库, 状态信息)。
    """
    query_params_base = {}
    if email:
        query_params_base["email"] = email
    if api_key:
        query_params_base["api_key"] = api_key

    for db in db_priority:
        # 针对不同数据库选择更合适的检索字段，提升命中率
        field = "Accession"
        if db == "assembly":
            field = "Assembly Accession"
        search_term = f"{accession}[{field}]"

        search_params = {
            "db": db,
            "term": search_term,
            "retmode": "json",
            "retmax": 1,
        }
        search_params.update(query_params_base)
        search_url = f"{EUTILS_BASE}/esearch.fcgi?{urlencode(search_params)}"
        try:
            with urlopen(search_url) as response:
                search_data = json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError) as exc:
            return None, None, f"HTTP error on esearch: {exc}"
        except Exception as exc:  # noqa: BLE001
            return None, None, f"esearch failure: {exc}"

        idlist = search_data.get("esearchresult", {}).get("idlist", [])
        if not idlist:
            time.sleep(delay)
            continue

        uid = idlist[0]
        summary_params = {"db": db, "id": uid, "retmode": "json"}
        summary_params.update(query_params_base)
        summary_url = f"{EUTILS_BASE}/esummary.fcgi?{urlencode(summary_params)}"
        try:
            with urlopen(summary_url) as response:
                summary_data = json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError) as exc:
            return None, None, f"HTTP error on esummary: {exc}"
        except Exception as exc:  # noqa: BLE001
            return None, None, f"esummary failure: {exc}"

        result_block = summary_data.get("result", {})
        summary_item = result_block.get(uid, {})
        taxid = summary_item.get("taxid")
        if taxid is None and db == "sra":
            expxml = summary_item.get("expxml", "")
            match = re.search(r'taxid="([0-9]+)"', expxml)
            if match:
                taxid = match.group(1)
        if taxid:
            time.sleep(delay)
            return str(taxid), db, "ok"

        time.sleep(delay)

    return None, None, "TaxID not found"
