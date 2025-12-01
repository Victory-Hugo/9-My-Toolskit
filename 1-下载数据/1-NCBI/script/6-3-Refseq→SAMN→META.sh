#!/bin/bash
# 下载 BioSample XML 文件到本地
# 用法：bash biosample_xml_download.sh

unset http_proxy
unset https_proxy


# 输入：只含 biosample ID 的纯文本（每行一个）
INFILE="/mnt/d/迅雷下载/鲍曼组装/conf/AB_Biosample_sort.txt"
# 输出目录：保存XML文件的目录
XML_DIR="/mnt/d/迅雷下载/鲍曼组装/xml2"

# 创建输出目录
mkdir -p "$XML_DIR"

# 简单检查输入文件
if [[ ! -f "$INFILE" ]]; then
  echo "ERROR: 输入文件不存在: $INFILE" >&2
  exit 1
fi

# 读取 BioSample 列表：去 CRLF、去空行、去首尾空白、去注释行、去重
mapfile -t BIOSAMPLES < <(
  sed -e 's/\r$//' "$INFILE" \
    | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); if($0!="" && $0 !~ /^#/) print $0 }' \
    | sort -u
)

if (( ${#BIOSAMPLES[@]} == 0 )); then
  echo "WARN: 未从 $INFILE 读取到任何 BioSample ID" >&2
  exit 0
fi

echo "开始下载 ${#BIOSAMPLES[@]} 个 BioSample 的 XML 文件到 $XML_DIR"

# 下载单个 BioSample XML 文件
download_xml() {
  local bs="$1"
  local xml_file="$XML_DIR/${bs}.xml"
  
  echo "正在下载: $bs"
  
  # 下载XML并保存到文件
  if esearch -db biosample -query "$bs" | efetch -format xml > "$xml_file"; then
    # 检查文件是否为空或包含错误信息
    if [[ -s "$xml_file" ]] && grep -q "<BioSample" "$xml_file"; then
      echo "  成功: $xml_file"
      return 0
    else
      echo "  失败: XML文件为空或格式错误"
      rm -f "$xml_file"
      return 1
    fi
  else
    echo "  失败: 无法下载 $bs"
    rm -f "$xml_file"
    return 1
  fi
}

# 统计变量
success_count=0
failed_count=0
skipped_count=0

# 主循环：逐个下载XML文件
for bs in "${BIOSAMPLES[@]}"; do
  # 检查文件是否已存在
  if [[ -f "$XML_DIR/${bs}.xml" ]]; then
    echo "跳过（文件已存在）: ${bs}.xml"
    ((skipped_count++))
  elif download_xml "$bs"; then
    ((success_count++))
  else
    ((failed_count++))
  fi
  
  # 控制请求频率，避免被NCBI限制
  sleep 0.1
done

echo ""
echo "下载完成！"
echo "成功: $success_count"
echo "跳过: $skipped_count" 
echo "失败: $failed_count"
echo "XML文件保存在: $XML_DIR"
