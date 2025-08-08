#!/bin/bash
set -euo pipefail

#TODO替换路径
PYTHON="/home/luolintao/miniconda3/envs/pyg/bin/python3"
SCRIPT_1="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/python/0-csv→SRR.py"
SCRIPT_2="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/python/0-csv→Run_Sample.py"
# 输入输出文件路径
INPUT="/mnt/c/Users/Administrator/Desktop/PRJNA778930_runinfo.csv"
OUTPUT1="/mnt/c/Users/Administrator/Desktop/RUN_ID.txt"
OUTPUT2="/mnt/c/Users/Administrator/Desktop/SAMPLE_RUN_ID.txt"


#* 运行 Python 脚本,从csv文件提取下载的RUN_ID
"$PYTHON" "$SCRIPT_1" "$INPUT" "$OUTPUT1"
#* 运行 Python 脚本,从csv文件得到SAMPLE_RUN_ID
"$PYTHON" "$SCRIPT_2" "$INPUT" "$OUTPUT2"

echo "输出文件：$OUTPUT1"
echo "输出文件：$OUTPUT2"
