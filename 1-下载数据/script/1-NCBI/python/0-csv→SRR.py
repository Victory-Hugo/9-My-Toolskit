# -*- coding: utf-8 -*-
"""
本代码的功能：
将NCBI数据库下载的`csv`文件中的SRR提取出来
形成一个新的txt文档。
本代码通过shell传入2个参数：
    1.输入文件路径
    2.输出文件路径
"""

import pandas as pd

def extract_accession(input_file, output_file):
    """
    从输入的csv文件中提取Accession列，并保存到输出文件。
    
    :param input_file: 输入的csv文件路径
    :param output_file: 输出的txt文件路径
    """
    # 读取csv文件
    df = pd.read_csv(input_file, sep=',', usecols=['Run'])
    
    # 提取Run列
    accession_list = df['Run'].tolist()
    
    # 将结果写入输出文件
    with open(output_file, 'w') as f:
        for accession in accession_list:
            f.write(f"{accession}\n")

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3:
        print("Usage: python 1.py <input_file> <output_file>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    extract_accession(input_file, output_file)
