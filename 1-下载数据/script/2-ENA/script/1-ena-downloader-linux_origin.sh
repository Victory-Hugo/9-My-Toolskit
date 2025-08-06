#!/usr/bin/env bash
set -uuo pipefail  # 遇到未定义变量退出

# ---------------------- 默认配置（可通过环境/CLI 覆盖） -----------------------
BASE_DIR='/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA'
JAVA_SOFT_PATH="${BASE_DIR}/func/ena-file-downloader.jar"
ACC_FILE='/mnt/f/OneDrive/文档（共享）/4_古代DNA/ERR_aDNA_batch3.txt'
ASPERA_PATH='/home/luolintao/miniconda3/pkgs/aspera-cli-3.9.6-h5e1937b_0'
FORMAT='READS_FASTQ'
PROTOCOL='ASPERA'
OUTPUT_DIR='/mnt/d/迅雷下载/ENA'
#* 进入输出目录
cd ${OUTPUT_DIR}
# ---------------------- 参数解析 -----------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --accessions) ACC_FILE="$2"; shift 2;;
    --output) OUTPUT_DIR="$2"; shift 2;;
    --jar) JAVA_SOFT_PATH="$2"; shift 2;;
    --aspera) ASPERA_PATH="$2"; shift 2;;
    --format) FORMAT="$2"; shift 2;;
    --protocol) PROTOCOL="$2"; shift 2;;
    --help)
      cat <<EOF
用法: $0 [--accessions <file>] [--output <dir>] [--jar <path>] [--aspera <path>] [--format <fmt>] [--protocol <PROTO>]
EOF
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      exit 1
      ;;
  esac
done

# ---------------------- 目录和日志 -----------------------
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_DIR="${OUTPUT_DIR%/}/logs"
mkdir -p "$OUTPUT_DIR" "$LOG_DIR"
MAIN_LOG="${LOG_DIR}/download_ena.${TIMESTAMP}.log"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$MAIN_LOG"
}

# ---------------------- 依赖检查 -----------------------
log "开始依赖检查..."
command -v java >/dev/null 2>&1 || { log "找不到 java，可执行程序需要 java 运行。"; exit 1; }
[[ -f "$JAVA_SOFT_PATH" ]] || { log "找不到 ENA downloader jar: ${JAVA_SOFT_PATH}"; exit 1; }

if [[ "$PROTOCOL" == "ASPERA" ]]; then
  if ! command -v ascp >/dev/null 2>&1; then
    export PATH="${ASPERA_PATH}/bin:$PATH"
  fi
  command -v ascp >/dev/null 2>&1 || { log "Aspera CLI (ascp) 无法找到，请确认安装并在 PATH 或 ASPERA_PATH/bin 下。"; exit 1; }
fi

[[ -f "$ACC_FILE" ]] || { log "找不到 accession 列表文件: ${ACC_FILE}"; exit 1; }
log "依赖检查通过。"

# ---------------------- 去重 accession 列表 -----------------------
ACC_DEDUP=$(mktemp)
awk 'NF && $0 !~ /^#/ {print $1}' "$ACC_FILE" | awk '!seen[$0]++' > "$ACC_DEDUP"
if [[ ! -s "$ACC_DEDUP" ]]; then
  log "去重后 accession 为空，退出。"
  rm -f "$ACC_DEDUP"
  exit 1
fi
uniq_count=$(wc -l < "$ACC_DEDUP")
log "去重后共 ${uniq_count} 个 accession，将一次性传给 Java 下载。"

# ---------------------- 运行 Java 一次性下载 -----------------------
log "调用 Java 开始下载..."
if java -jar "$JAVA_SOFT_PATH" \
    --accessions="$ACC_DEDUP" \
    --format="$FORMAT" \
    --location="$OUTPUT_DIR" \
    --protocol="$PROTOCOL" \
    --asperaLocation="${ASPERA_PATH}" \
    --email=None \
    >>"$MAIN_LOG" 2>&1; then
  log "Java 下载命令返回成功。"
else
  log "Java 下载命令失败，请查看日志: ${MAIN_LOG}"
  rm -f "$ACC_DEDUP"
  exit 1
fi

log "下载流程完成。请根据 Java 输出 / 目标目录内容确认成功与否。"
rm -f "$ACC_DEDUP"
exit 0
