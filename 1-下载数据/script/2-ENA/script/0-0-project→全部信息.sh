#!/usr/bin/env bash
set -uo pipefail

#TODO 修改下列
PROJECT="PRJEB32764" #todo 需要查询的项目编号
BASE_DIR="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA" #todo 脚本所在目录
OUTPUT="${BASE_DIR}/conf/aDNA.tsv" #todo 中间文件输出文件路径
# 写死的路径
PYTHON="/home/luolintao/miniconda3/envs/pyg/bin/python3" # todo Python 解释器路径
SCRIPT="${BASE_DIR}/python/0-tsv→txt.py" #todo Python 脚本路径
OUTPUT_TXT="${BASE_DIR}/conf/aDNA.txt" #todo 最终输出文件路径




#*============无需修改系列的内容=====================
# ENA API 字段
FIELDS="run_accession,sample_accession,experiment_accession,study_accession,tax_id,scientific_name,base_count,fastq_ftp,fastq_md5"
ENA_API="https://www.ebi.ac.uk/ena/portal/api/filereport"
LOG="/tmp/get_${PROJECT}_$(date '+%Y%m%d_%H%M%S').log"
RETRY=3

# 输入输出文件路径
INPUT="${OUTPUT}"
# 写表头（制表符分隔）
echo -e "run_accession\tsample_accession\texperiment_accession\tstudy_accession\ttax_id\tscientific_name\tbase_count\tfastq_ftp\tfastq_md5" > "$OUTPUT"

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
