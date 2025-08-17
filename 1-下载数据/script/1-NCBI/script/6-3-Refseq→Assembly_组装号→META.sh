#!/bin/bash
# 查询 BioSample 元数据（Description / Submitter / Collected by / Geographic location）
# 用法：bash biosample_fetch.sh

unset http_proxy
unset https_proxy
set -euo pipefail

# 输入：只含 biosample ID 的纯文本（每行一个）
INFILE="/mnt/d/迅雷下载/鲍曼组装/conf/AB_Biosample.txt"
# 输出：带元数据的 tsv（直接写入，无临时文件）
OUT_FILE="/mnt/d/迅雷下载/鲍曼组装/conf/AB_Biosample_META_more.tsv"

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

# 写表头（直接覆盖 OUT_FILE）
echo -e "BioSampleAccn\tDescription\tSubmitter\tCollected_by\tGeographic_location\tHost\tCollection_date\tLatitude_and_longitude" > "$OUT_FILE"

if (( ${#BIOSAMPLES[@]} == 0 )); then
  echo "WARN: 未从 $INFILE 读取到任何 BioSample ID" >&2
  echo "完成：已创建空表头 -> $OUT_FILE"
  exit 0
fi

# 查询函数：保持你原来的 xtract 字段顺序与行为
fetch_one() {
  local bs="$1"
  local line
  if ! line="$(
    esearch -db biosample -query "$bs" \
      | efetch -format xml \
      | xtract \
          -pattern BioSample \
          -block Description -element Title \
          -block Owner -element Name \
          -block Attribute -if Attribute@attribute_name -equals "collected_by" -element Attribute \
          -block Attribute -if Attribute@attribute_name -equals "geo_loc_name" -element Attribute \
          -block Attribute -if Attribute@attribute_name -equals "geographic location (country and/or sea)" -element Attribute \
          -block Attribute -if Attribute@attribute_name -equals "geographic location (region and locality)" -element Attribute \
          -block Attribute -if Attribute@attribute_name -equals "host" -element Attribute \
          -block Attribute -if Attribute@attribute_name -equals "collection_date" -element Attribute \
          -block Attribute -if Attribute@attribute_name -equals "lat_lon" -element Attribute 
  )"; then
    # 查询失败时输出 NA 行（追加到 OUT_FILE）
    echo -e "${bs}\tNA\tNA\tNA\tNA\tNA\tNA\tNA" >> "$OUT_FILE"
    return
  fi

  # 解析 xtract 返回的字段（Title Name collected_by geo_loc_name host collection_date lat_lon）
  IFS=$'\t' read -r title name collected geo_loc_name host collection_date lat_lon <<< "$line"
  local geo="NA"
  
  # 使用 geo_loc_name 作为地理位置
  if [[ -n "$geo_loc_name" && "$geo_loc_name" != "NA" ]]; then
    geo="$geo_loc_name"
  fi

  echo -e "${bs}\t${title:-NA}\t${name:-NA}\t${collected:-NA}\t${geo}\t${host:-NA}\t${collection_date:-NA}\t${lat_lon:-NA}" >> "$OUT_FILE"
}

# 主循环：逐个查询（直接追加到 OUT_FILE）
for bs in "${BIOSAMPLES[@]}"; do
  fetch_one "$bs"
  # 保留原来 sleep 节奏（必要时可放大以避免 NCBI 限流）
  sleep 0.01
done

echo "完成：结果已保存到 $OUT_FILE"
