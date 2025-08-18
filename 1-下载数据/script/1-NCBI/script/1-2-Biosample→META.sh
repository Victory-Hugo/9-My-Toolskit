: '
脚本功能说明：
本脚本用于批量查询 NCBI BioSample 数据库中的样本元数据，
包括 Description、Submitter、Collected by 和 Geographic location 信息，并将结果保存为 TSV 文件。
#!2025年8月18日更新：不建议使用如下脚本获取信息，因为获取的信息不完善。
#!建议使用1-下载数据/script/1-NCBI/script/6-3-Refseq→Assembly_组装号→META.sh获取最完整的信息
主要流程：
1. 读取指定项目的 runinfo.csv 文件，自动检测分隔符（支持 TAB、逗号、分号、竖线）。
2. 自动查找 BioSampleAccn 或 BioSample 列，提取所有唯一的 BioSample ID。
3. 通过 NCBI Entrez 工具（esearch、efetch、xtract）查询每个 BioSample 的元数据信息。
4. 优先使用 geo_loc_name 字段作为地理位置信息，若无则组合 country 和 region 字段。
5. 将所有结果写入输出文件（TSV 格式），包含表头。
6. 支持异常处理，若查询失败则填充 NA。

使用方法：
bash biosample_fetch.sh input.csv

依赖工具：
- NCBI Entrez Direct (esearch, efetch, xtract)
- awk, sort, head, tr, mapfile

注意事项：
- 输入文件需包含 BioSampleAccn 或 BioSample 列。
- 需提前安装 NCBI Entrez Direct 工具。
- 脚本自动处理代理设置，适合在无代理环境下运行。
'
#!/bin/bash
# 查询 BioSample 元数据（Description / Submitter / Collected by / Geographic location）
# 用法：bash biosample_fetch.sh input.csv
unset http_proxy
unset https_proxy
set -euo pipefail
PROJ="PRJNA572371"
INFILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/conf/${PROJ}_runinfo.csv"
OUT_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/conf/${PROJ}_biosample.tsv"

# 判断分隔符
header="$(head -n 1 "$INFILE" | tr -d '\r')"
if [[ "$header" == *$'\t'* ]]; then
  DELIM=$'\t'
elif [[ "$header" == *","* ]]; then
  DELIM=','
elif [[ "$header" == *";"* ]]; then
  DELIM=';'
elif [[ "$header" == *"|"* ]]; then
  DELIM='|'
else
  DELIM=$'\t'
  echo "WARN: 未检测到常见分隔符，默认按 TAB 解析。" >&2
fi

# 查找列号
get_col_index() {
  local name="$1"
  awk -v FS="$DELIM" -v target="$name" '
    NR==1 {
      for (i=1; i<=NF; i++) {
        col=$i
        gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", col)
        if (tolower(col) == tolower(target)) { print i; exit }
      }
    }' "$INFILE"
}

col_idx="$(get_col_index 'BioSampleAccn')"
if [[ -z "$col_idx" ]]; then
  col_idx="$(get_col_index 'BioSample')"
fi
if [[ -z "$col_idx" ]]; then
  echo "ERROR: 未找到 BioSampleAccn 或 BioSample 列" >&2
  exit 1
fi

# 提取唯一 BioSample ID
mapfile -t BIOSAMPLES < <(
  awk -v FS="$DELIM" -v C="$col_idx" 'NR>1 {v=$C; gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", v); if(v!="") print v}' "$INFILE" \
    | sort -u
)

# 写表头
echo -e "BioSampleAccn\tDescription\tSubmitter\tCollected_by\tGeographic_location" > "$OUT_FILE"

# 查询函数
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
          -block Attribute -if Attribute@attribute_name -equals "geographic location (region and locality)" -element Attribute
  )"; then
    echo -e "${bs}\tNA\tNA\tNA\tNA" >> "$OUT_FILE"
    return
  fi

  IFS=$'\t' read -r title name collected geo_loc_name geo_country geo_region <<< "$line"
  local geo="NA"
  
  # 优先使用 geo_loc_name
  if [[ -n "$geo_loc_name" && "$geo_loc_name" != "NA" ]]; then
    geo="$geo_loc_name"
  elif [[ -n "$geo_country" && "$geo_country" != "NA" ]]; then
    geo="$geo_country"
    if [[ -n "$geo_region" && "$geo_region" != "NA" ]]; then
      geo="$geo; $geo_region"
    fi
  elif [[ -n "$geo_region" && "$geo_region" != "NA" ]]; then
    geo="$geo_region"
  fi

  echo -e "${bs}\t${title:-NA}\t${name:-NA}\t${collected:-NA}\t${geo}" >> "$OUT_FILE"
}

# 主循环
for bs in "${BIOSAMPLES[@]}"; do
  fetch_one "$bs"
  sleep 0.01
done

echo "完成：结果已保存到 $OUT_FILE"
