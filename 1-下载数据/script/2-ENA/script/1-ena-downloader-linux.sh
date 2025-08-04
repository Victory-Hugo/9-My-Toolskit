#!/usr/bin/env bash
set -uo pipefail  # 不用 -e，内部手动控制失败逻辑以支持重试/续跑

# ---------------------- 默认配置（可通过环境/CLI 覆盖） -----------------------
#TODO 1. 定义变量：ENA downloader 的 jar 包路径
#TODO 2. 定义 accession 列表文件（每行一个 accession）
BASE_DIR='/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA'
JAVA_SOFT_PATH="${BASE_DIR}/func/ena-file-downloader.jar"
ACC_FILE='/mnt/f/OneDrive/文档（共享）/4_古代DNA/aDNA.txt'

#TODO 3. 定义 Aspera CLI 的安装路径
#TODO 具体路径请根据实际安装位置修改
#! 注意：Aspera CLI 需要先安装，具体安装方法请参考相关文档
#! 强烈的推荐使用conda安装 Aspera CLI：
#* `conda install -y -c hcc aspera-cli`
#* 在使用Aspera CLI 前，请确保已安装 Aspera CLI。如果需要配置秘钥，可以复制下方的秘钥。
#* 我将秘钥复制了一份放在了ASPERA_DSA_SSH="${BASE_DIR}/conf/asperaweb_id_dsa.openssh"
ASPERA_PATH='/home/luolintao/miniconda3/pkgs/aspera-cli-3.9.6-h5e1937b_0'
ASPERA_DSA_SSH="${BASE_DIR}/conf/asperaweb_id_dsa.openssh"

#TODO 3. 定义下载输出目录（根据需要修改）
OUTPUT_DIR='/mnt/d/迅雷下载/ENA'
#TODO 4. 定义下载格式（可选：READS_FASTQ, READS_SUBMITTED, READS_BAM 等）
#TODO 具体格式请查看`1-下载数据/script/2-ENA/markdown/0-阅读我.md`
FORMAT='READS_FASTQ'
PROTOCOL='ASPERA'

#TODO 5. 定义最大重试次数和重试间隔（秒）
#TODO 这些参数可以根据网络状况和数据大小调整
MAX_RETRIES=3
RETRY_BASE_DELAY=5  # 秒
CONCURRENT_LOCK="/tmp/$(basename "$0").lock"

# ---------------------- 可通过环境变量/参数覆盖 -----------------------
# 例如：ACC_FILE=xxx OUTPUT_DIR=yyy ./download_ena.sh
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
可配置项覆盖：ACC_FILE, OUTPUT_DIR, JAVA_SOFT_PATH, ASPERA_PATH
EOF
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      exit 1
      ;;
  esac
done

# ---------------------- 目录/文件准备 -----------------------
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_DIR="${OUTPUT_DIR%/}/logs"
mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

MAIN_LOG="${LOG_DIR}/download_ena.${TIMESTAMP}.log"
DONE_FILE="${LOG_DIR}/done.list"
FAILED_FILE="${LOG_DIR}/failed.list"
TMP_LOCK_PID_FILE="${CONCURRENT_LOCK}"

# --------------- 并发保护（简单 lockfile） -----------------
acquire_lock() {
  if [[ -f "$TMP_LOCK_PID_FILE" ]]; then
    existing_pid=$(<"$TMP_LOCK_PID_FILE")
    if ps -p "$existing_pid" > /dev/null 2>&1; then
      echo "另一个实例正在运行（PID $existing_pid），退出。" | tee -a "$MAIN_LOG"
      exit 1
    else
      echo "发现遗留锁，但进程 $existing_pid 不存在，清理后继续。" | tee -a "$MAIN_LOG"
      rm -f "$TMP_LOCK_PID_FILE"
    fi
  fi
  echo $$ > "$TMP_LOCK_PID_FILE"
  trap release_lock EXIT INT TERM
}

release_lock() {
  rm -f "$TMP_LOCK_PID_FILE"
}

# ------------------- 日志辅助 -------------------
log() {
  local msg="$1"
  echo "[$(date '+%F %T')] $msg" | tee -a "$MAIN_LOG"
}

# ------------------- 依赖检查 -------------------
check_prereqs() {
  log "开始依赖检查..."
  command -v java >/dev/null 2>&1 || { echo "找不到 java，可执行程序需要 java 运行。" | tee -a "$MAIN_LOG"; exit 1; }
  [[ -f "$JAVA_SOFT_PATH" ]] || { echo "找不到 ENA downloader jar: ${JAVA_SOFT_PATH}" | tee -a "$MAIN_LOG"; exit 1; }
  if [[ "$PROTOCOL" == "ASPERA" ]]; then
    [[ -d "$ASPERA_PATH" ]] || { echo "找不到 Aspera CLI 路径: ${ASPERA_PATH}" | tee -a "$MAIN_LOG"; exit 1; }
    # 可选：检查 ascp 是否可用（假定在 ASPERA_PATH 下的 bin）
    if ! command -v ascp >/dev/null 2>&1; then
      export PATH="${ASPERA_PATH}/bin:$PATH"
    fi
    command -v ascp >/dev/null 2>&1 || { echo "Aspera CLI (ascp) 无法找到，请确认安装并在 PATH 或 ASPERA_PATH/bin 下。" | tee -a "$MAIN_LOG"; exit 1; }
  fi
  [[ -f "$ACC_FILE" ]] || { echo "找不到 accession 列表文件: ${ACC_FILE}" | tee -a "$MAIN_LOG"; exit 1; }
  log "依赖检查通过。"
}

# ------------------- 下载单个 accession（含重试） -------------------
download_accession() {
  local acc="$1"
  local attempt=0
  while (( attempt < MAX_RETRIES )); do
    ((attempt++))
    log "开始下载 accession '${acc}'（尝试 ${attempt}/${MAX_RETRIES}）"
    if java -jar "$JAVA_SOFT_PATH" \
        --accessions="${acc}" \
        --format="${FORMAT}" \
        --location="${OUTPUT_DIR}" \
        --protocol="${PROTOCOL}" \
        --asperaLocation="${ASPERA_PATH}" \
        --email=None \
        >>"$MAIN_LOG" 2>&1; then
      log "accession '${acc}' 下载成功。"
      echo "$acc" >> "$DONE_FILE"
      return 0
    else
      log "accession '${acc}' 下载失败（第 ${attempt} 次）。"
      sleep $(( RETRY_BASE_DELAY * attempt ))
    fi
  done

  log "accession '${acc}' 多次尝试失败，记录到 failed.list。"
  echo "$acc" >> "$FAILED_FILE"
  return 1
}

# ------------------- 判断是否已完成 -------------------
is_done() {
  local acc="$1"
  grep -Fxq "$acc" "$DONE_FILE" 2>/dev/null
}

# ------------------- 主流程 -------------------
main() {
  acquire_lock
  check_prereqs

  # 读入 accession 去重、保留原始顺序
  mapfile -t all_accs < <(awk 'NF && $0 !~ /^#/' "$ACC_FILE" | awk '{print $1}' | awk '!seen[$0]++')
  total=${#all_accs[@]}
  log "总共读取到 ${total} 个 accession。"

  processed=0
  succeeded=0
  failed=0

  for acc in "${all_accs[@]}"; do
    ((processed++))
    if is_done "$acc"; then
      log "[$processed/$total] '${acc}' 已标记为完成，跳过。"
      ((succeeded++))
      continue
    fi

    log "[$processed/$total] 处理 '${acc}' ..."
    if download_accession "$acc"; then
      ((succeeded++))
    else
      ((failed++))
    fi
  done

  log "=== 运行结束 ==="
  log "总数: ${total}, 成功: ${succeeded}, 失败: ${failed}, 已完成列表: ${DONE_FILE}, 失败列表: ${FAILED_FILE}"

  if (( failed > 0 )); then
    echo "有 ${failed} 个 accession 失败，可以查看 ${FAILED_FILE} 重新手动/脚本重试。" | tee -a "$MAIN_LOG"
    exit 2
  fi
}

# ------------------- 执行 -------------------
main


# #* 基础命令
# # -k1：启用断点续传。
# # -l 100m：限制下载速度为 100 Mbps。
# # -P33001：指定 Aspera 端口。
# # -Q：quiet 模式，抑制常规的进度/统计输出，只在出错时显示。用在脚本/批量里可以减少噪音。
# # -T：关闭传输内容的加密，让 FASP 以“非加密”模式跑数据。
# # 注意这会降低传输的保密性，但对公开的 ENA/SRA 数据影响不大，因为内容本身是公开的。
# /home/luolintao/miniconda3/pkgs/aspera-cli-3.9.6-h5e1937b_0/bin/ascp
# /home/luolintao/miniconda3/envs/pyg/bin/ascp \
#   -QT \
#   -l 100m \
#   -P33001 \
#   -k1 \
#   -i "${ASPERA_DSA_SSH}" \
#   era-fasp@fasp.sra.ebi.ac.uk:/vol1/fastq/SRR142/075/SRR14209175/SRR14209175.fastq.gz \
#   "${OUTPUT_DIR}/SRR14209175.fastq.gz"