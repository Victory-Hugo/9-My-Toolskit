#!/bin/bash
# 从 Run accession (ERR/SRR/DRR) 获取 BioSample (SAMN) 并下载 BioSample XML
# 顺序执行，带断点续跑
# 输出 Run ↔ SAMN 对照表为 CSV

unset http_proxy
unset https_proxy

# 输入文件：Run ID 列表
INFILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/conf/鲍曼NC2025.txt"
# 输出目录
XML_DIR="/mnt/d/迅雷下载/鲍曼组装/xml"
# Run↔SAMN 对照表
CSV_FILE="$XML_DIR/run_biosample_map.csv"

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

echo "开始处理 ${#RUNS[@]} 个 Run ID (顺序执行)"

# 初始化 CSV 文件（断点续跑时保留已有）
if [[ ! -f "$CSV_FILE" ]]; then
  echo "Run_ID,BioSample" > "$CSV_FILE"
fi

# 单个任务
process_run() {
  local run="$1"
  echo "处理 Run: $run"

  # 如果 CSV 中已有该 run → 读取 BioSample
  local existing_bs
  existing_bs=$(grep "^${run}," "$CSV_FILE" | cut -d',' -f2)

  if [[ -n "$existing_bs" ]]; then
    local xml_file="$XML_DIR/${existing_bs}.xml"
    if [[ -s "$xml_file" ]] && grep -q "<BioSample" "$xml_file"; then
      echo "  跳过（CSV+XML 已存在）: $run → $existing_bs"
      return 0
    else
      echo "  XML 文件缺失或错误，重试: $run → $existing_bs"
      rm -f "$xml_file"
    fi
  fi

  # 获取 BioSample
  local bs
  bs=$(esearch -db sra -query "$run" | efetch -format runinfo | cut -d',' -f26 | tail -n1)

  if [[ -z "$bs" ]]; then
    echo "  错误: 未找到 BioSample for $run"
    # 补空行到 CSV（仅第一次）
    if ! grep -q "^${run}," "$CSV_FILE"; then
      echo "$run," >> "$CSV_FILE"
    fi
    return 1
  fi

  # 写入 CSV（避免重复）
  if ! grep -q "^${run}," "$CSV_FILE"; then
    echo "$run,$bs" >> "$CSV_FILE"
  fi

  # 下载 XML（最多尝试 3 次）
  local xml_file="$XML_DIR/${bs}.xml"
  local attempt=1
  local success=0

  while (( attempt <= 3 )); do
    echo "  下载尝试 $attempt: $bs"
    if esearch -db biosample -query "$bs" | efetch -format xml > "$xml_file"; then
      if [[ -s "$xml_file" ]] && grep -q "<BioSample" "$xml_file"; then
        echo "  成功: $xml_file"
        success=1
        break
      else
        echo "  警告: XML 文件为空或错误 (attempt $attempt)"
        rm -f "$xml_file"
      fi
    else
      echo "  错误: 下载失败 (attempt $attempt)"
      rm -f "$xml_file"
    fi
    ((attempt++))
    sleep 1
  done

  if (( success == 0 )); then
    echo "  失败: $run → $bs"
    return 1
  fi
}

# 顺序执行
for run in "${RUNS[@]}"; do
  process_run "$run"
  sleep 0.1   # 防止 NCBI 限制
done

echo ""
echo "全部任务完成！"
echo "Run↔SAMN 对照表: $CSV_FILE"
echo "XML 文件目录: $XML_DIR"
