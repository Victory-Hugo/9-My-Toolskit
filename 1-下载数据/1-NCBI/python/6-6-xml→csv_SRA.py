#!/usr/bin/env python3
# coding: utf-8
"""
6-6-xml→csv.py
用法:
    python3 6-6-xml→csv.py <input.xml> <output_dir>

说明:
    - 更鲁棒地提取 LIBRARY_NAME、不同 PLATFORM（ILLUMINA / LS454 / ...）下的 INSTRUMENT_MODEL
    - 提取 SAMPLE_ATTRIBUTE 中的所有 tag/value（比如 strain, geo_loc_name 等）
    - 提取 Run-level 的统计信息（total_spots, total_bases, Read count/average/stdev）和碱基计数
"""

import sys
import os
import xml.etree.ElementTree as ET
import pandas as pd

def first_text_by_tags(root, tag_names):
    """在文档中按顺序查找任意 tag_names 中的第一个元素文本并返回（若无则返回空串）"""
    for t in tag_names:
        el = root.find(".//" + t)
        if el is not None and el.text:
            return el.text.strip()
    return ""

def find_instrument_model(root):
    """查找任意 PLATFORM 下的 INSTRUMENT_MODEL（支持 ILLUMINA, LS454 等）"""
    # 直接查找任何 INSTRUMENT_MODEL 节点
    im = root.find(".//INSTRUMENT_MODEL")
    if im is not None and im.text:
        return im.text.strip()
    # 兼容：有些 XML 结构可能是 <PLATFORM><ILLUMINA><INSTRUMENT_MODEL>...</INSTRUMENT_MODEL></ILLUMINA></PLATFORM>
    # 上面的 find 已能匹配到，但保留此函数以便后续扩展
    return ""

def parse_sample_attributes(sample_elem):
    """返回 dict: tag -> value，遍历 SAMPLE_ATTRIBUTE 元素"""
    d = {}
    if sample_elem is None:
        return d
    for attr in sample_elem.findall(".//SAMPLE_ATTRIBUTE"):
        tag_el = attr.find("TAG")
        val_el = attr.find("VALUE")
        if tag_el is not None:
            tag = (tag_el.text or "").strip()
            val = (val_el.text or "").strip() if val_el is not None else ""
            if tag:
                d[tag] = val
    return d

def parse_base_counts(run_elem):
    """解析 Bases/Base 元素，返回 dict value->count"""
    d = {}
    if run_elem is None:
        return d
    for base in run_elem.findall(".//Bases/Base"):
        val = base.attrib.get("value") or (base.findtext("value") or "")
        count = base.attrib.get("count") or (base.findtext("count") or "")
        # attr form used in many SRA XMLs: <Base value="A" count="29068466"/>
        if not val and base.get("value"):
            val = base.get("value")
        if not count and base.get("count"):
            count = base.get("count")
        if val:
            try:
                d[val] = int(count) if str(count).isdigit() else count
            except:
                d[val] = count
    return d

def parse_read_stats(run_elem):
    """解析 <Statistics><Read .../> 元素，返回 count, average, stdev （若存在，取 index=0）"""
    if run_elem is None:
        return {}
    read_el = run_elem.find(".//Statistics/Read")
    if read_el is None:
        # 有时直接在 Statistics/Read[@index='0'] 出现多个 Read，尝试找 index='0'
        for r in run_elem.findall(".//Statistics/Read"):
            if r.attrib.get("index") in (None, "0", "00", "0"):
                read_el = r
                break
    if read_el is None:
        return {}
    out = {}
    for k in ("count", "average", "stdev"):
        v = read_el.attrib.get(k)
        if v is None:
            # 也可能以子元素存在（少见）
            v = read_el.findtext(k, default="")
        # 转数值（若可能）
        try:
            if v != "" and ('.' in v or 'e' in v.lower()):
                out[k] = float(v)
            elif v != "":
                out[k] = int(v)
            else:
                out[k] = ""
        except:
            out[k] = v
    return out

def parse_xml_to_row(xml_file):
    tree = ET.parse(xml_file)
    root = tree.getroot()

    # 找到常用节点（取第一个匹配）
    run = root.find(".//RUN")
    experiment = root.find(".//EXPERIMENT")
    study = root.find(".//STUDY")
    sample = root.find(".//SAMPLE")

    samp_attrs = parse_sample_attributes(sample)

    # library name 常见位置: <LIBRARY_NAME> 或 <LIBRARY_DESCRIPTOR>/<LIBRARY_NAME>
    library_name = first_text_by_tags(root, ["LIBRARY_NAME", "LIBRARY_DESCRIPTOR/LIBRARY_NAME"])

    # sequencing platform model（常见位置: <PLATFORM>/<ILLUMINA>/<INSTRUMENT_MODEL> 或 <PLATFORM>/<LS454>/<INSTRUMENT_MODEL>）
    instrument_model = find_instrument_model(root)

    # library strategy / source / layout
    lib_strategy = first_text_by_tags(root, ["LIBRARY_STRATEGY", "LIBRARY_DESCRIPTOR/LIBRARY_STRATEGY"])
    lib_source = first_text_by_tags(root, ["LIBRARY_SOURCE", "LIBRARY_DESCRIPTOR/LIBRARY_SOURCE"])

    # Library layout: 单端/双端
    lib_layout = ""
    if root.find(".//LIBRARY_LAYOUT/SINGLE") is not None or root.find(".//LIBRARY_DESCRIPTOR/LIBRARY_LAYOUT/SINGLE") is not None:
        lib_layout = "SINGLE"
    elif root.find(".//LIBRARY_LAYOUT/PAIRED") is not None or root.find(".//LIBRARY_DESCRIPTOR/LIBRARY_LAYOUT/PAIRED") is not None:
        lib_layout = "PAIRED"
    else:
        # 退而求其次：查看 LIBRARY_LAYOUT 子节点名字
        ll = root.find(".//LIBRARY_LAYOUT")
        if ll is not None and len(list(ll)) > 0:
            lib_layout = list(ll)[0].tag

    # run-level attributes
    total_reads = run.attrib.get("total_spots") if run is not None else ""
    total_bases = run.attrib.get("total_bases") if run is not None else ""
    run_accession = run.attrib.get("accession") if run is not None else ""
    experiment_accession = experiment.attrib.get("accession") if experiment is not None else ""
    study_accession = study.attrib.get("accession") if study is not None else ""
    sample_accession = sample.attrib.get("accession") if sample is not None else ""

    read_stats = parse_read_stats(run)
    base_counts = parse_base_counts(run)

    row = {
        "Run Accession": run_accession,
        "Experiment Accession": experiment_accession,
        "Study Accession": study_accession,
        "BioProject ID": first_text_by_tags(root, ["EXTERNAL_ID[@namespace='BioProject']", "EXTERNAL_ID"]),
        "Sample Accession": sample_accession,
        "BioSample ID": first_text_by_tags(root, ["EXTERNAL_ID[@namespace='BioSample']", "EXTERNAL_ID"]),
        "Organism": first_text_by_tags(root, ["SCIENTIFIC_NAME", "SAMPLE_NAME/SCIENTIFIC_NAME"]),
        "Strain": samp_attrs.get("strain", ""),
        "Taxon ID": first_text_by_tags(root, ["TAXON_ID", "SAMPLE_NAME/TAXON_ID"]),
        "Geo Location": samp_attrs.get("geo_loc_name", samp_attrs.get("geo-location", "")),
        "Isolation Source": samp_attrs.get("env_medium", ""),
        "Relationship": samp_attrs.get("biotic_relationship", ""),
        "Oxygen Requirement": samp_attrs.get("rel_to_oxygen", ""),
        "Trophic Level": samp_attrs.get("trophic_level", ""),
        "Library Name": library_name,
        "Sequencing Platform": instrument_model,
        "Library Strategy": lib_strategy,
        "Library Source": lib_source,
        "Library Layout": lib_layout,
        "Total Reads": int(total_reads) if str(total_reads).isdigit() else total_reads,
        "Total Bases": int(total_bases) if str(total_bases).isdigit() else total_bases,
        "Read Count": read_stats.get("count", ""),
        "Average Read Length": read_stats.get("average", ""),
        "Read Length StdDev": read_stats.get("stdev", ""),
        # 基址计数 A/C/G/T/N（如果存在）
        "Base A": base_counts.get("A", ""),
        "Base C": base_counts.get("C", ""),
        "Base G": base_counts.get("G", ""),
        "Base T": base_counts.get("T", ""),
        "Base N": base_counts.get("N", "")
    }

    # 把 SAMPLE_ATTRIBUTE 的其他常见 tag 也展平为列（可选）
    # 只添加尚未存在的键
    for k, v in samp_attrs.items():
        col = f"sample_attr:{k}"
        if col not in row:
            row[col] = v

    return row

def main():
    if len(sys.argv) != 3:
        print("用法: python3 6-6-xml→csv.py <input.xml> <output_dir>")
        sys.exit(1)

    xml_file = sys.argv[1]
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    row = parse_xml_to_row(xml_file)
    df = pd.DataFrame([row])

    base_name = os.path.splitext(os.path.basename(xml_file))[0] + ".csv"
    out_file = os.path.join(out_dir, base_name)
    df.to_csv(out_file, index=False)
    print(f"写出: {out_file}")

if __name__ == "__main__":
    main()
