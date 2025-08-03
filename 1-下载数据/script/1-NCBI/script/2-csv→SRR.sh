#!/bin/bash
set -euo pipefail

# 写死的路径
PYTHON="/home/luolintao/miniconda3/envs/pyg/bin/python3"
SCRIPT="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/python/0-csv→SRR.py"
# 输入输出文件路径
INPUT="/mnt/c/Users/Administrator/Desktop/PRJNA778930_runinfo.csv"
OUTPUT="/mnt/c/Users/Administrator/Desktop/aDNA.txt"

# 运行 Python 脚本
"$PYTHON" "$SCRIPT" "$INPUT" "$OUTPUT"

echo "输出文件：$OUTPUT"
