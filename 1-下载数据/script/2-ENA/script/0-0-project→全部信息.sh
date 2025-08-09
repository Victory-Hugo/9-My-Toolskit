: '
脚本名称: 0-0-project→全部信息.sh

用途:
  该脚本用于通过 ENA (European Nucleotide Archive) API 查询指定项目编号（PROJECT）的 run 级别信息（如 run_accession、sample_accession、fastq_ftp、fastq_md5 等），并将结果保存为 tsv 文件，最后调用 Python 脚本进一步处理为 txt 文件。

主要流程:
  1. 设置项目编号、Python 解释器路径、脚本路径及输出文件路径等参数。
  2. 通过 ENA API 查询指定项目编号的 run 信息，支持多次重试，自动处理异常和空结果。
  3. 将查询结果写入 tsv 文件，并去重（保留表头）。
  4. 调用指定 Python 脚本对 tsv 文件进行进一步处理，生成最终 txt 文件。
  5. 日志信息输出到临时日志文件，便于排查问题。

主要变量说明:
  PROJECT      - 需要查询的 ENA 项目编号
  PYTHON       - Python 解释器路径
  BASE_DIR     - 脚本所在目录
  SCRIPT       - Python 脚本路径
  OUTPUT       - 中间 tsv 输出文件路径
  OUTPUT_TXT   - 最终 txt 输出文件路径
  FIELDS       - ENA API 查询字段
  ENA_API      - ENA API 地址
  LOG          - 日志文件路径
  RETRY        - 查询失败时的最大重试次数

主要函数说明:
  log()        - 日志输出函数
  urlencode()  - URL 编码函数，优先使用 python3
  query_project() - 查询 ENA 项目编号的 run 信息，处理异常和空结果

使用方法:
  1. 修改脚本开头的 PROJECT、PYTHON、BASE_DIR、SCRIPT、OUTPUT、OUTPUT_TXT 等参数为实际需求。
  2. 运行脚本，自动获取并处理 ENA 项目信息，最终输出 txt 文件。

注意事项:
  - 需保证网络可访问 ENA API。
  - 需安装 curl、awk、python3 等依赖。
  - Python 脚本需自行实现并放置于指定路径。
'
#!/usr/bin/env bash
set -uo pipefail

#TODO 修改下列
PROJECT="PRJEB39316" #todo 需要查询的项目编号
PYTHON="/home/luolintao/miniconda3/envs/pyg/bin/python3" # todo Python 解释器路径
BASE_DIR="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA" #todo 脚本所在目录
# 写死的路径
SCRIPT="${BASE_DIR}/python/0-tsv→txt.py" #todo Python 脚本路径
OUTPUT="${BASE_DIR}/conf/aDNA.tsv" #todo 中间文件输出文件路径
OUTPUT_TXT="${BASE_DIR}/conf/aDNA.txt" #todo 最终输出文件路径




#*============无需修改系列的内容=====================
# ENA API 字段
FIELDS="run_accession,sample_accession,sample_alias,study_title,experiment_accession,study_accession,tax_id,scientific_name,base_count,fastq_ftp,fastq_md5"
ENA_API="https://www.ebi.ac.uk/ena/portal/api/filereport"
LOG="/tmp/get_${PROJECT}_$(date '+%Y%m%d_%H%M%S').log"
RETRY=3

# 输入输出文件路径
INPUT="${OUTPUT}"
# 写表头（制表符分隔）
echo -e "run_accession\tsample_accession\tsample_alias\tstudy_title\texperiment_accession\tstudy_accession\ttax_id\tscientific_name\tbase_count\tfastq_ftp\tfastq_md5" > "$OUTPUT"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG" >&2
}

urlencode() {
  # 只编码必要部分，借助 python3 安全处理
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "$1"
import sys, urllib.parse
print(urllib.parse.quote_plus(sys.argv[1]))
PY
  else
    # 退而求其次的简单替换
    echo -n "$1" | sed -e 's/ /%20/g' -e 's/"/%22/g' -e "s/'/%27/g"
  fi
}

query_project() {
  local acc="$1"
  local encoded
  encoded=$(urlencode "$acc")
  local url="${ENA_API}?accession=${encoded}&result=read_run&fields=${FIELDS}&format=tsv"
  local attempt=0
  while (( attempt < RETRY )); do
    ((attempt++))
    log "请求 ENA: ${acc}（第 ${attempt} 次）"
    # 失败不 set -e 所以手动检查
    resp=$(curl -fsS --max-time 60 "$url") || {
      log "警告：访问 ENA 失败（attempt=${attempt})，等待再重试..."
      sleep $((2 ** attempt))
      continue
    }
    if [[ -z "$resp" ]]; then
      log "注意：ENA 返回空，accession=${acc}"
      # 生成空行占位（sample_accession 为原 project，其他字段空）
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "" "$acc" "" "" "" "" "" "" "" >> "$OUTPUT"
      return 0
    fi

    # 解析结果（保留 header 之后的行）
    data=$(printf '%s\n' "$resp" | awk 'NR>1')

    if [[ -n "$data" ]]; then
      # 追加所有 run 记录（可能多行）
      printf '%s\n' "$data" >> "$OUTPUT"
      log "成功获取 ${acc} 的 ${#data[@]} 行数据。"
    else
      log "查询到但没有数据（只有 header），accession=${acc}"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "" "$acc" "" "" "" "" "" "" "" >> "$OUTPUT"
    fi
    return 0
  done

  log "错误：多次尝试仍无法获取 ${acc}，写占位空行。"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "" "$acc" "" "" "" "" "" "" "" >> "$OUTPUT"
  return 1
}

# 主逻辑
log "开始为 project ${PROJECT} 获取 run 级别 fastq_ftp 和 fastq_md5 信息。输出: ${OUTPUT}"
query_project "$PROJECT"

# 去重（可选，防止重复 run），保持 header
if command -v awk >/dev/null 2>&1; then
  # 保留 header，去掉后面重复行
  { head -n1 "$OUTPUT"; tail -n +2 "$OUTPUT" | sort -u; } > "${OUTPUT}.tmp" && mv "${OUTPUT}.tmp" "$OUTPUT"
  log "去重完成（如果有重复行）。"
fi

log "完成。结果保存在：${OUTPUT}"

# 运行 Python 脚本
"$PYTHON" "$SCRIPT" "$INPUT" "$OUTPUT_TXT"

echo "输出文件：$OUTPUT_TXT"
