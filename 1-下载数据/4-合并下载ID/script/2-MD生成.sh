#!/bin/bash
set -euo pipefail

SEARCH_DIR="/mnt/c/Users/Administrator/Desktop"
OUTPUT="/mnt/c/Users/Administrator/Desktop/fastq_md5.csv"

# 写表头
echo '"file_path","md5"' > "$OUTPUT"

# 找 .fastq 和 .fastq.gz （如果只要 .fastq 去掉 -o -name '*.fastq.gz' 那段）
find "$SEARCH_DIR" -type f \( -name '*.fastq' -o -name '*.fastq.gz' \) -print0 \
  | while IFS= read -r -d '' f; do
      # 计算 md5（文件本身）
      if ! md5=$(md5sum "$f" 2>/dev/null | awk '{print $1}'); then
          echo "警告: 计算 $f 的 md5 失败" >&2
          continue
      fi
      # 处理路径中的双引号（CSV 里用双引号包裹，内部双引号翻倍）
      esc_path=${f//\"/\"\"}
      printf '"%s","%s"\n' "$esc_path" "$md5" >> "$OUTPUT"
      echo "已处理: $f" >&2
  done

echo "完成，结果写在 $OUTPUT"
