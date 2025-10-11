#!/usr/bin/env python3
"""
ENA BAM文件链接拆分脚本
用于处理ENA项目的TSV文件，根据数据类型生成相应的下载链接和MD5文件

使用方法:
python 2-ENA-BAM-链接拆分.py <输入TSV文件路径> [输出目录路径]

如果不指定输出目录，将使用输入文件所在目录
"""

import pandas as pd
import os
import sys
import argparse


def print_color(text, color_code):
    """打印彩色文本"""
    print(f"\033[{color_code}m{text}\033[0m")


def process_bam_files(df, project_name, output_dir):
    """处理BAM文件链接和MD5"""
    bam_urls = []
    bai_urls = []
    bam_md5s = []
    bai_md5s = []
    
    for idx, row in df.iterrows():
        if pd.notna(row['submitted_ftp']) and pd.notna(row['submitted_md5']):
            ftp_links = row['submitted_ftp'].split(';')
            md5_values = row['submitted_md5'].split(';')
            
            for ftp, md5 in zip(ftp_links, md5_values):
                if ftp.endswith('.bam'):
                    bam_urls.append(ftp.strip())
                    bam_md5s.append(f"{md5.strip()}  {os.path.basename(ftp.strip())}")
                elif ftp.endswith('.bai'):
                    bai_urls.append(ftp.strip())
                    bai_md5s.append(f"{md5.strip()}  {os.path.basename(ftp.strip())}")
    
    # 写入文件
    with open(f"{output_dir}/{project_name}_bam.url", 'w') as f:
        f.write('\n'.join(bam_urls))
    
    with open(f"{output_dir}/{project_name}_bam_bai.url", 'w') as f:
        f.write('\n'.join(bai_urls))
    
    with open(f"{output_dir}/{project_name}_bam.md5", 'w') as f:
        f.write('\n'.join(bam_md5s))
    
    with open(f"{output_dir}/{project_name}_bam_bai.md5", 'w') as f:
        f.write('\n'.join(bai_md5s))
    
    return len(bam_urls), len(bai_urls)


def main():
    parser = argparse.ArgumentParser(description='ENA BAM文件链接拆分工具')
    parser.add_argument('input_tsv', help='输入的TSV文件路径')
    parser.add_argument('output_dir', nargs='?', help='输出目录路径（可选，默认为输入文件所在目录）')
    
    args = parser.parse_args()
    
    # 检查输入文件是否存在
    if not os.path.exists(args.input_tsv):
        print_color(f"错误：输入文件不存在: {args.input_tsv}", "31")
        sys.exit(1)
    
    # 设置输出目录
    if args.output_dir:
        output_dir = args.output_dir
        # 创建输出目录（如果不存在）
        os.makedirs(output_dir, exist_ok=True)
    else:
        output_dir = os.path.dirname(args.input_tsv)
    
    # 获取项目名称
    project_name = os.path.basename(args.input_tsv).replace('.tsv', '')
    
    print_color(f"输入文件: {args.input_tsv}", "36")
    print_color(f"输出目录: {output_dir}", "36")
    print_color(f"项目名称: {project_name}", "36")
    print("-" * 50)
    
    # 读取TSV文件
    try:
        df = pd.read_csv(args.input_tsv, sep="\t")
        print_color(f"成功读取TSV文件，共 {len(df)} 行数据", "32")
    except Exception as e:
        print_color(f"错误：无法读取TSV文件: {e}", "31")
        sys.exit(1)
    
    # 检查数据类型并处理
    if df['fastq_ftp'].isnull().all() and df['submitted_ftp'].isnull().all():
        print_color("[fastq:NO] [bam:NO]", "31")  # 红色
        print_color("请仔细检查该项目是否有数据!", "31")  # 红色
        print_color("建议使用以下脚本重新准备信息:", "31")  # 红色
        print_color("1-下载数据/script/2-ENA/script/0-0-project→全部信息.sh", "31")  # 红色
        print_color("代码终止执行", "31")
        sys.exit(1)
        
    elif df['fastq_ftp'].isnull().all() and not df['submitted_ftp'].isnull().all():
        print_color("[fastq:NO] [bam:YES]", "32")  # 绿色
        print_color("开始处理BAM文件链接和MD5...", "32")  # 绿色
        
        bam_count, bai_count = process_bam_files(df, project_name, output_dir)
        
        print_color(f"已生成文件:", "32")
        print_color(f"- {project_name}_bam.url ({bam_count} 个BAM文件)", "32")
        print_color(f"- {project_name}_bam_bai.url ({bai_count} 个BAI文件)", "32")
        print_color(f"- {project_name}_bam.md5", "32")
        print_color(f"- {project_name}_bam_bai.md5", "32")
        print_color("[有BAM文件，建议1-0-ascp下载BAM.sh下载BAM文件]", "34")
        print_color("[有BAM文件，建议1-0-ascp下载BAM.sh下载BAM文件]", "34")
        print_color("[有BAM文件，建议1-0-ascp下载BAM.sh下载BAM文件]", "34")
        print_color("[有BAM文件，建议1-0-ascp下载BAM.sh下载BAM文件]", "34")
        
    elif not df['fastq_ftp'].isnull().all() and df['submitted_ftp'].isnull().all():
        print_color("[fastq:YES] [bam:NO]", "33")  # 黄色
        print_color("警告：只存在FASTQ文件，不建议使用ENA下载器，因为太慢！", "33")
        print_color("建议使用NCBI的SRA工具下载，因为稳定且快！", "33")
        print_color("推荐使用以下文件和脚本:", "33")
        print_color(f"- 配置文件: 1-下载数据/script/2-ENA/conf/{project_name}.txt", "33")
        print_color("- 下载脚本: 1-下载数据/script/1-NCBI/script/3-NCBI-SRA-download.sh", "33")
        print_color("- 下载脚本: 1-下载数据/script/1-NCBI/script/3-NCBI-SRA-download.sh", "33")
        print_color("- 下载脚本: 1-下载数据/script/1-NCBI/script/3-NCBI-SRA-download.sh", "33")
        print_color("- 下载脚本: 1-下载数据/script/1-NCBI/script/3-NCBI-SRA-download.sh", "33")
        
    else:
        print_color("[fastq:YES] [bam:YES]", "34")  # 青色
        print_color("检测到FASTQ和BAM文件都存在，建议下载BAM文件！", "34")
        print_color("开始处理BAM文件链接和MD5...", "34")
        
        bam_count, bai_count = process_bam_files(df, project_name, output_dir)
        
        print_color(f"已生成文件:", "34")
        print_color(f"- {project_name}_bam.url ({bam_count} 个BAM文件)", "34")
        print_color(f"- {project_name}_bam_bai.url ({bai_count} 个BAI文件)", "34")
        print_color(f"- {project_name}_bam.md5", "34")
        print_color(f"- {project_name}_bam_bai.md5", "34")
        print_color("[有BAM文件，建议1-0-ascp下载BAM.sh下载BAM文件]", "34")
        print_color("[有BAM文件，建议1-0-ascp下载BAM.sh下载BAM文件]", "34")
        print_color("[有BAM文件，建议1-0-ascp下载BAM.sh下载BAM文件]", "34")
        print_color("[有BAM文件，建议1-0-ascp下载BAM.sh下载BAM文件]", "34")
    
    print_color("处理完成！", "32")


if __name__ == "__main__":
    main()