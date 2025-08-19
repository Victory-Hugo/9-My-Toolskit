#!/bin/bash
# 从 GCF/GCA accession 获取 Assembly 的 BioSample (SAMN) 并下载 XML
# 自动补全标准 Accession（带版本号）
# 顺序执行（非并行）
# 输出 XML 文件 + CSV 对照表（Input_ID ↔ Standard_ID ↔ SAMN ↔ Organism）
# 支持断点续跑

unset http_proxy
unset https_proxy

# 输入文件：GCF/GCA 列表（可能缺少版本号）
INFILE="/mnt/d/迅雷下载/鲍曼组装/conf/AB_Assembly.txt"
# 输出目录
XML_DIR="/mnt/d/迅雷下载/鲍曼组装/xml2"
# CSV 对照表
CSV_FILE="$XML_DIR/assembly_biosample_map.csv"

mkdir -p "$XML_DIR"

if [[ ! -f "$INFILE" ]]; then
  echo "ERROR: 输入文件不存在: $INFILE" >&2
  exit 1
fi

# 去重、清理输入
mapfile -t ASMS < <(
  sed -e 's/\r$//' "$INFILE" \
    | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); if($0!="" && $0 !~ /^#/) print $0 }' \
    | sort -u
)

if (( ${#ASMS[@]} == 0 )); then
  echo "WARN: 未从 $INFILE 读取到任何 Assembly ID" >&2
  exit 0
fi

echo "开始处理 ${#ASMS[@]} 个 Assembly ID (顺序执行)"

# 如果 CSV 不存在就初始化表头
if [[ ! -f "$CSV_FILE" ]]; then
  echo "Input_ID,Standard_ID,BioSample,Organism" > "$CSV_FILE"
fi

# 重试函数
retry_esearch() {
  local query="$1"
  local db="$2"
  local max_retries=3
  local retry_count=0
  local result=""
  
  while (( retry_count < max_retries )); do
    result=$(esearch -db "$db" -query "$query" 2>/dev/null)
    if [[ -n "$result" ]]; then
      echo "$result"
      return 0
    fi
    ((retry_count++))
    echo "    重试 $retry_count/$max_retries ..." >&2
    sleep $((retry_count * 2))  # 递增等待时间
  done
  return 1
}

# 安全下载 XML - 使用 BioSample ID 下载，而不是 Assembly ID
safe_download_xml() {
  local samn_id="$1"
  local output_file="$2"
  local max_retries=3
  local retry_count=0
  
  if [[ -z "$samn_id" ]] || [[ "$samn_id" == "SAMN" ]]; then
    echo "    跳过下载：无效的 BioSample ID" >&2
    return 1
  fi
  
  while (( retry_count < max_retries )); do
    # 清空文件以防止部分下载
    > "$output_file"
    
    # 使用 BioSample ID 下载 XML，而不是 Assembly ID
    if esearch -db biosample -query "$samn_id" | efetch -format xml > "$output_file" 2>/dev/null; then
      # 检查文件是否有实际内容（大于 50 字节）
      if [[ -s "$output_file" ]] && (( $(stat -c%s "$output_file") > 50 )); then
        return 0
      fi
    fi
    
    ((retry_count++))
    echo "    XML下载重试 $retry_count/$max_retries ..." >&2
    sleep $((retry_count * 3))  # 递增等待时间
  done
  
  # 删除失败的空文件
  rm -f "$output_file"
  return 1
}

# 单个任务
process_asm() {
  local input_id="$1"

  echo "处理 Input: $input_id"

  # 获取标准化 Accession（带版本号）
  local full_acc
  full_acc=$(retry_esearch "$input_id" "assembly" | efetch -format docsum 2>/dev/null | \
             xtract -pattern DocumentSummary -element AssemblyAccession | head -n1)

  if [[ -z "$full_acc" ]]; then
    echo "  错误: 未找到标准 Accession for $input_id"
    if ! grep -q "^${input_id}," "$CSV_FILE"; then
      echo "$input_id,,," >> "$CSV_FILE"
    fi
    return 1
  fi

  local xml_file="$XML_DIR/${full_acc}.xml"

  # 从 docsum 提取信息（使用正确的字段名）
  local info
  info=$(retry_esearch "$full_acc" "assembly" | efetch -format docsum 2>/dev/null | \
         xtract -pattern DocumentSummary -element AssemblyAccession BioSampleAccn Organism | head -n1)

  local std_acc samn org
  std_acc=$(echo "$info" | cut -f1)
  samn=$(echo "$info" | cut -f2)
  org=$(echo "$info" | cut -f3-)

  if [[ -z "$samn" ]]; then
    echo "  警告: 未找到 BioSample for $full_acc"
    samn=""
  fi

  # 如果 CSV 已有该条目，跳过
  if grep -q "^${input_id},${full_acc}," "$CSV_FILE"; then
    echo "  跳过（CSV已存在）: $input_id → $full_acc → $samn"
    return 0
  fi

  # 下载 BioSample XML（如果有 SAMN ID）
  if [[ -n "$samn" ]]; then
    local xml_file="$XML_DIR/${samn}.xml"
    
    if [[ ! -f "$xml_file" ]] || [[ ! -s "$xml_file" ]] || (( $(stat -c%s "$xml_file") <= 50 )); then
      echo "  下载 BioSample XML: $samn"
      if ! safe_download_xml "$samn" "$xml_file"; then
        echo "  警告: BioSample XML下载失败 $samn"
      fi
    else
      echo "  BioSample XML已存在: $samn"
    fi
  fi

  # 写入 CSV（避免重复）
  if ! grep -q "^${input_id},${full_acc}," "$CSV_FILE"; then
    echo "$input_id,$std_acc,$samn,\"$org\"" >> "$CSV_FILE"
  fi

  echo "  完成: $input_id → $std_acc → $samn"
}

# 顺序循环执行
for asm in "${ASMS[@]}"; do
  process_asm "$asm"
  sleep 0.1   # 增加延迟避免请求过快被 NCBI 屏蔽
done

echo ""
echo "全部任务完成！"
echo "CSV 对照表: $CSV_FILE"
echo "XML 文件目录: $XML_DIR"
