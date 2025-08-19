#!/bin/bash
# 从 Run accession (ERR/SRR/DRR) 获取 BioSample (SAMN) 并下载 BioSample XML
# 支持并行处理、API密钥、断点续跑
# 输出 Run ↔ SAMN 对照表为 CSV
# 作者：Lintao Luo
# 日期：2025年8月19日

unset http_proxy
unset https_proxy

# 默认配置
INFILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/conf/鲍曼NC2025.txt"
XML_DIR="/mnt/d/迅雷下载/鲍曼组装/xml"
CSV_FILE="$XML_DIR/run_biosample_map.csv"
LOG_FILE="$XML_DIR/run_biosample_log.txt"
DEFAULT_PARALLEL_JOBS=8  # 默认并行任务数

# NCBI API配置
NCBI_API_KEY="29b326d54e7a21fc6c8b9afe7d71f441d809"
export NCBI_API_KEY

# 并行任务数（可通过命令行参数调整）
PARALLEL_JOBS=${1:-$DEFAULT_PARALLEL_JOBS}

# 验证并行任务数
if [[ ! "$PARALLEL_JOBS" =~ ^[0-9]+$ ]] || [ "$PARALLEL_JOBS" -lt 1 ] || [ "$PARALLEL_JOBS" -gt 20 ]; then
    echo "错误: 并行任务数必须是1-20之间的整数"
    echo "使用方法: $0 [并行任务数]"
    echo "示例: $0 8  # 使用8个并行任务"
    exit 1
fi

mkdir -p "$XML_DIR"

if [[ ! -f "$INFILE" ]]; then
  echo "ERROR: 输入文件不存在: $INFILE" >&2
  exit 1
fi

# 去重、清理输入
mapfile -t RUNS < <(
  sed -e 's/\r$//' "$INFILE" \
    | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); if($0!="" && $0 !~ /^#/) print $0 }' \
    | sort -u
)

if (( ${#RUNS[@]} == 0 )); then
  echo "WARN: 未从 $INFILE 读取到任何 Run ID" >&2
  exit 0
fi

echo "开始处理 ${#RUNS[@]} 个 Run ID (使用 $PARALLEL_JOBS 个并行任务)"

# 初始化日志文件
init_log_file() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "# Run->BioSample Download Log - Created on $(date)" > "$LOG_FILE"
        echo "# Format: TIMESTAMP | RUN_ID | STATUS | BIOSAMPLE_ID | XML_FILE | NOTES" >> "$LOG_FILE"
        echo "# STATUS: SUCCESS/FAILED/SKIPPED" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
}

# 记录日志的函数
log_result() {
    local run_id="$1"
    local status="$2"
    local biosample_id="$3"
    local xml_file="$4"
    local notes="$5"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp | $run_id | $status | $biosample_id | $xml_file | $notes" >> "$LOG_FILE"
}

# 检查Run是否已经成功处理
is_run_completed() {
    local run_id="$1"
    if [ -f "$LOG_FILE" ]; then
        grep -q "| $run_id | SUCCESS |" "$LOG_FILE"
        return $?
    fi
    return 1
}

# 获取失败的Run列表
get_failed_runs() {
    if [ -f "$LOG_FILE" ]; then
        grep "| FAILED |" "$LOG_FILE" | cut -d'|' -f2 | tr -d ' ' | sort -u
    fi
}

# 初始化文件
init_log_file

# 初始化 CSV 文件（断点续跑时保留已有）
if [[ ! -f "$CSV_FILE" ]]; then
  echo "Run_ID,BioSample" > "$CSV_FILE"
fi

# 单个任务
process_run() {
  local run="$1"
  local current="$2"
  local total="$3"
  
  # 去除可能的空白字符
  run=$(echo "$run" | tr -d '[:space:]')
  
  # 跳过空的run_id
  if [ -z "$run" ]; then
      echo "跳过空的run_id"
      return
  fi
  
  echo "[$current/$total] 处理 Run: $run (PID: $$)"

  # 检查是否已经成功处理过
  if is_run_completed "$run"; then
      echo "  [$$] ✓ Run $run 已在之前成功处理，跳过"
      log_result "$run" "SKIPPED" "PREVIOUSLY_COMPLETED" "EXISTING" "Previously completed successfully"
      return
  fi

  # 如果 CSV 中已有该 run → 读取 BioSample
  local existing_bs
  existing_bs=$(grep "^${run}," "$CSV_FILE" | cut -d',' -f2)

  if [[ -n "$existing_bs" ]] && [[ "$existing_bs" != "" ]]; then
    local xml_file="$XML_DIR/${existing_bs}.xml"
    if [[ -s "$xml_file" ]] && grep -q "<BioSample" "$xml_file"; then
      echo "  [$$] ✓ 跳过（CSV+XML 已存在）: $run → $existing_bs"
      log_result "$run" "SUCCESS" "$existing_bs" "$xml_file" "Previously downloaded"
      return 0
    else
      echo "  [$$] XML 文件缺失或错误，重试: $run → $existing_bs"
      rm -f "$xml_file"
    fi
  fi

  # 获取 BioSample
  echo "  [$$] 正在获取 BioSample ID..."
  local bs
  bs=$(esearch -db sra -query "$run" | efetch -format runinfo | cut -d',' -f26 | tail -n1 2>/dev/null)

  if [[ -z "$bs" ]] || [[ "$bs" == "BioSample" ]]; then
    echo "  [$$] ✗ 错误: 未找到 BioSample for $run"
    log_result "$run" "FAILED" "NOT_FOUND" "" "BioSample not found in SRA"
    # 补空行到 CSV（仅第一次）
    if ! grep -q "^${run}," "$CSV_FILE"; then
      echo "$run," >> "$CSV_FILE"
    fi
    return 1
  fi

  echo "  [$$] ✓ 找到 BioSample: $bs"

  # 写入 CSV（避免重复）
  if ! grep -q "^${run}," "$CSV_FILE"; then
    echo "$run,$bs" >> "$CSV_FILE"
  fi

  # 下载 XML（最多尝试 3 次）
  local xml_file="$XML_DIR/${bs}.xml"
  local attempt=1
  local success=0

  while (( attempt <= 3 )); do
    echo "  [$$] 下载尝试 $attempt: $bs"
    if esearch -db biosample -query "$bs" | efetch -format xml > "$xml_file" 2>/dev/null; then
      if [[ -s "$xml_file" ]] && grep -q "<BioSample" "$xml_file"; then
        echo "  [$$] ✓ 成功: $xml_file"
        log_result "$run" "SUCCESS" "$bs" "$xml_file" "Downloaded successfully"
        success=1
        break
      else
        echo "  [$$] ⚠ 警告: XML 文件为空或错误 (attempt $attempt)"
        rm -f "$xml_file"
      fi
    else
      echo "  [$$] ✗ 错误: 下载失败 (attempt $attempt)"
      rm -f "$xml_file"
    fi
    ((attempt++))
    sleep 1
  done

  if (( success == 0 )); then
    echo "  [$$] ✗ 失败: $run → $bs"
    log_result "$run" "FAILED" "$bs" "" "XML download failed after 3 attempts"
    return 1
  fi
}

# 导出函数供并行处理使用
export -f process_run
export -f is_run_completed
export -f log_result
export CSV_FILE XML_DIR LOG_FILE NCBI_API_KEY

# 使用并行处理
echo "使用 $PARALLEL_JOBS 个并行任务处理 ${#RUNS[@]} 个 Run ID..."
printf '%s\n' "${RUNS[@]}" | nl -nln | xargs -n1 -P"$PARALLEL_JOBS" -I{} bash -c '
    line="{}"
    current=$(echo "$line" | cut -f1)
    run=$(echo "$line" | cut -f2)
    total='"${#RUNS[@]}"'
    process_run "$run" "$current" "$total"
    sleep 0.1
'

echo ""
echo "全部任务完成！"
echo "Run↔SAMN 对照表: $CSV_FILE"
echo "XML 文件目录: $XML_DIR"

# 显示统计信息
xml_count=$(find "$XML_DIR" -name "*.xml" 2>/dev/null | wc -l)
echo ""
echo "统计信息："
echo "- 成功获取的BioSample XML: $xml_count 个"

# 显示日志统计
if [ -f "$LOG_FILE" ]; then
    echo ""
    echo "详细统计（基于日志文件）："
    success_count=$(grep -c "| SUCCESS |" "$LOG_FILE" 2>/dev/null || echo "0")
    failed_count=$(grep -c "| FAILED |" "$LOG_FILE" 2>/dev/null || echo "0")
    skipped_count=$(grep -c "| SKIPPED |" "$LOG_FILE" 2>/dev/null || echo "0")
    
    echo "- 成功处理: $success_count 个"
    echo "- 处理失败: $failed_count 个"
    echo "- 已跳过: $skipped_count 个"
    
    # 显示失败的Run
    failed_runs=$(get_failed_runs)
    if [ -n "$failed_runs" ]; then
        echo ""
        echo "需要重新处理的失败Run："
        echo "$failed_runs"
        
        # 创建失败Run的重试文件
        retry_file="$XML_DIR/retry_runs.txt"
        echo "$failed_runs" > "$retry_file"
        echo ""
        echo "失败Run已保存到: $retry_file"
        echo "可以使用以下命令重新处理失败的Run："
        echo "  sed -i 's|INFILE=.*|INFILE=\"$retry_file\"|' $0"
        echo "  $0"
    fi
fi

echo ""
echo "断点续跑功能："
echo "- 脚本会记录每个Run的处理状态到日志文件"
echo "- 重新运行脚本时会自动跳过已成功处理的Run"
echo "- 失败的Run会记录详细错误信息，方便后续重试"
echo "- 日志文件位置: $LOG_FILE"
echo ""
echo "脚本支持并行处理，可通过命令行参数调整并行数："
echo "  $0           # 使用默认并行数 ($DEFAULT_PARALLEL_JOBS) - API密钥优化"
echo "  $0 8         # 使用8个并行任务"
echo "  $0 1         # 单线程处理（最安全，但最慢）"
echo "  $0 12        # 使用12个并行任务（API密钥支持高并发）"
echo ""
echo "API密钥优势："
echo "- 10次/秒的请求限制（vs 普通3次/秒）"
echo "- 支持更高的并行数（5-12个任务）"
echo "- 更稳定的服务质量"
