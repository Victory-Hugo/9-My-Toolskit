#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 脚本：download_ena.sh
# 功能：调用 ENA File Downloader，根据 list.txt 中的 accession 列表批量下载 FASTQ
# 使用：chmod +x download_ena.sh && ./download_ena.sh
# -----------------------------------------------------------------------------
#TODO 1. 定义变量：ENA downloader 的 jar 包路径
#TODO 2. 定义 accession 列表文件（每行一个 accession）
BASE_DIR='/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/'
JAVA_SOFT_PATH="${BASE_DIR}/func/ena-file-downloader.jar"
ACC_FILE="/mnt/f/OneDrive/文档（共享）/4_古代DNA/SAMEA_aDNA.txt"

#TODO 3. 定义下载输出目录（根据需要修改）
OUTPUT_DIR='/mnt/d/迅雷下载/ENA/'

#TODO 4. 定义下载格式（可选：READS_FASTQ, READS_SUBMITTED, READS_BAM 等）
#TODO 具体格式请查看`1-下载数据/script/2-ENA/markdown/0-阅读我.md`
FORMAT='READS_FASTQ'
# FORMAT='READS_BAM'
# 5. 定义下载协议（FTP 或 ASPERA）
PROTOCOL='FTP'

# -----------------------------------------------------------------------------
# 方法一：直接让工具读取 list.txt （ENA 支持 --accessions=<file> 方式）
# -----------------------------------------------------------------------------
java -jar "${JAVA_SOFT_PATH}" \
  --accessions="${ACC_FILE}" \
  --format="${FORMAT}" \
  --location="${OUTPUT_DIR}" \
  --protocol="${PROTOCOL}"

# -----------------------------------------------------------------------------
# 方法二：如果希望在脚本内部拼接成逗号分隔的字符串，再传给 --accessions
# -----------------------------------------------------------------------------
# # 读取文件、去空行并拼接
# ACC_LIST=$(grep -v '^\s*$' "${ACC_FILE}" | paste -sd',' -)
#
# java -jar "${JAVA_SOFT_PATH}" \
#   --accessions="${ACC_LIST}" \
#   --format="${FORMAT}" \
#   --location="${OUTPUT_DIR}" \
#   --protocol="${PROTOCOL}"
