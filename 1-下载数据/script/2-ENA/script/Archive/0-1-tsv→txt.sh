#!/bin/bash
set -euo pipefail

# 写死的路径
PYTHON="/home/luolintao/miniconda3/envs/pyg/bin/python3"
SCRIPT="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/python/0-tsv→txt.py"
# 输入输出文件路径
INPUT="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf/aDNA.tsv"
OUTPUT="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf/aDNA.txt"

# 运行 Python 脚本
"$PYTHON" "$SCRIPT" "$INPUT" "$OUTPUT"

echo "输出文件：$OUTPUT"
