#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

########################################
# 写死的路径（请根据实际情况修改）
########################################
INPUT_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/conf/wget.txt"
OUTPUT_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/conf/url.txt"

########################################
# 检查输入文件是否存在
########################################
if [ ! -f "$INPUT_FILE" ]; then
  echo "错误：输入文件 '$INPUT_FILE' 不存在。" >&2
  exit 1
fi

########################################
# 提取 URL 到输出文件
########################################
# 使用 grep 提取所有以 http://、https:// 或 ftp:// 开头的 URL
grep -Eo '(https?://|ftp://)[^ ]+' "$INPUT_FILE" > "$OUTPUT_FILE"

echo "已将所有 URL 提取到：$OUTPUT_FILE"