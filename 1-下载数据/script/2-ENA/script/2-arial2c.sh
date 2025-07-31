#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

########################################
# 写死的路径（请根据实际情况修改）
########################################
URL_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/conf/url.txt"
OUT_DIR="/mnt/c/Users/Administrator/Desktop/"
SESSION_FILE="${OUT_DIR}/aria2.session"
LOG_FILE="${OUT_DIR}/download.log"

########################################
# 可配置参数（默认值如下，可在此处修改，或通过环境变量覆盖）
########################################
# 每个服务器的最大连接数
MAX_CONNECTION_PER_SERVER=${MAX_CONNECTION_PER_SERVER:-2}
# 每个文件的分片数
SPLIT=${SPLIT:-2}
# 最大并发下载数
MAX_CONCURRENT_DOWNLOADS=${MAX_CONCURRENT_DOWNLOADS:-4}

########################################
# 工具依赖检查
########################################
for cmd in aria2c md5sum; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "错误：未找到命令 '$cmd'，请先安装它。" >&2
    exit 2
  fi
done

########################################
# URL 列表和输出目录检查/创建
########################################
if [ ! -f "$URL_FILE" ]; then
  echo "错误：URL 列表文件 '$URL_FILE' 不存在。" >&2
  exit 3
fi

if [ ! -d "$OUT_DIR" ]; then
  echo "目标目录 '$OUT_DIR' 不存在，正在创建..."
  mkdir -p "$OUT_DIR"
fi

########################################
# 开始下载
########################################
echo "开始下载，日志见 $LOG_FILE"
aria2c \
  --input-file="$URL_FILE" \
  --dir="$OUT_DIR" \
  --continue=true \
  --max-connection-per-server="$MAX_CONNECTION_PER_SERVER" \
  --split="$SPLIT" \
  --max-concurrent-downloads="$MAX_CONCURRENT_DOWNLOADS" \
  --auto-file-renaming=false \
  --save-session="$SESSION_FILE" \
  --log="$LOG_FILE" \
  --log-level=info

########################################
# 下载完成后的 MD5 校验（可选）
########################################
echo "下载完成，开始 MD5 校验（如果有 .md5 文件）..."
while read -r url; do
  fn=$(basename "$url")
  if [ -f "${OUT_DIR}/${fn}.md5" ]; then
    echo "校验 ${fn} ..."
    pushd "$OUT_DIR" &>/dev/null
    if ! md5sum -c "${fn}.md5" &>>"$LOG_FILE"; then
      echo "!!! 校验失败：${fn}，将重新下载该文件" | tee -a "$LOG_FILE"
      rm -f "$fn" "$fn.aria2"
      aria2c \
        --dir="$OUT_DIR" \
        --continue=true \
        --max-connection-per-server="$MAX_CONNECTION_PER_SERVER" \
        --split="$SPLIT" \
        --auto-file-renaming=false \
        "$url" \
        &>>"$LOG_FILE"
      echo "重新下载完成：${fn}" | tee -a "$LOG_FILE"
    else
      echo "校验通过：${fn}" | tee -a "$LOG_FILE"
    fi
    popd &>/dev/null
  fi
done < "$URL_FILE"

echo "全部任务完成！"