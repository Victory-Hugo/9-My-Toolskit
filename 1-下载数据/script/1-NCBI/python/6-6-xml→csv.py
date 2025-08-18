#!/usr/bin/env python3
import sys
import os
import xml.etree.ElementTree as ET
import pandas as pd

def xml_to_csv(xml_path, out_dir):
    # 解析 XML
    tree = ET.parse(xml_path)
    root = tree.getroot()
    
    rows = []
    all_attrs = set()

    # 遍历所有 BioSample
    for biosample in root.findall("BioSample"):
        record = {
            "accession": biosample.attrib.get("accession"),
            "publication_date": biosample.attrib.get("publication_date")
        }
        
        # 提取 Attributes
        for attr in biosample.findall("Attributes/Attribute"):
            name = attr.attrib.get("attribute_name")
            value = attr.text
            record[name] = value
            all_attrs.add(name)
        
        rows.append(record)

    # 转换为 DataFrame
    df = pd.DataFrame(rows)

    # 确保所有属性列都存在
    for col in all_attrs:
        if col not in df.columns:
            df[col] = "NA"

    # 缺失值填充
    df = df.fillna("NA")

    # 输出路径
    base_name = os.path.splitext(os.path.basename(xml_path))[0]
    out_path = os.path.join(out_dir, base_name + ".csv")

    # 保存 CSV
    df.to_csv(out_path, index=False)
    return out_path

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"用法: {sys.argv[0]} input.xml output_directory")
        sys.exit(1)

    xml_file = sys.argv[1]
    out_dir = sys.argv[2]

    if not os.path.isdir(out_dir):
        print(f"错误: 输出目录不存在: {out_dir}")
        sys.exit(1)

    csv_file = xml_to_csv(xml_file, out_dir)
    print(f"输出文件: {csv_file}")
