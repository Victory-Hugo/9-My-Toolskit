#!/usr/bin/env bash
set -euo pipefail

URL_DIR="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf"
OUT_LIST="/mnt/c/Users/Administrator/Desktop/download1.txt"
SAVE_DIR="/mnt/c/Users/Administrator/Desktop"

# 清空或创建输出文件
: > "$OUT_LIST"

# 构造 download 列表
find "$URL_DIR" -type f -name "*.url" | while IFS= read -r url_file; do
    [ -r "$url_file" ] || continue
    grep -vE '^\s*#' "$url_file" | grep -vE '^\s*$' |
    while IFS= read -r line; do
        if [[ "$line" =~ ftp\.sra\.ebi\.ac\.uk/ ]]; then
            path_part="${line#*ftp.sra.ebi.ac.uk/}"
            echo "$path_part"
        else
            echo "$line"
        fi
    done
done | sort -u >> "$OUT_LIST"

# 检查生成的列表是否为空
if [ ! -s "$OUT_LIST" ]; then
    echo "ERROR: download list is empty: $OUT_LIST"
    exit 1
fi

# 下载函数：带重试
download_with_retries() {
    local retry_max=5
    local i=0
    until [ $i -ge $retry_max ]
    do
        ascli -Pera server download \
          --log-level=info \
          --sources=@lines:@file:"$OUT_LIST" \
          --to-folder="$SAVE_DIR" && break
        i=$((i + 1))
        echo "Download attempt $i failed. Retrying in 10s..."
        sleep 10
    done

    if [ $i -ge $retry_max ]; then
        echo "ERROR: All download attempts failed" >&2
        return 1
    fi
    return 0
}

# 主流程：启动下载
download_with_retries
