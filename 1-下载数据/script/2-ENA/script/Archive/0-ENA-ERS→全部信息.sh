#!/bin/bash
set -euo pipefail

input="/mnt/c/Users/Administrator/Desktop/1.TXT"     # 每行一个 ERS2540882 形式
output="/mnt/c/Users/Administrator/Desktop/ENA_full.tsv"

# 要的字段列表
FIELDS="run_accession,sample_accession,experiment_accession,study_accession,tax_id,scientific_name,base_count,fastq_ftp,sra_ftp,bam_ftp,bam_bytes,bam_md5"

# 写表头（和 API 返回一致）
echo -e "run_accession\tsample_accession\texperiment_accession\tstudy_accession\ttax_id\tscientific_name\tbase_count\tfastq_ftp\tsra_ftp\tbam_ftp\tbam_bytes\tbam_md5" > "$output"

while IFS= read -r ers; do
    # 跳过空行和注释
    [[ -z "${ers// /}" || "${ers:0:1}" == "#" ]] && continue
    ers=$(echo "$ers" | tr -d '\r' | awk '{$1=$1};1')  # trim

    echo "正在处理 $ers" >&2

    # 请求 ENA filereport
    resp=$(curl -s "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${ers}&result=read_run&fields=${FIELDS}&format=tsv")

    # 取除表头后的内容（如果有多个 run 会有多行）
    data=$(printf '%s\n' "$resp" | awk 'NR>1')

    if [[ -n "$data" ]]; then
        # 直接追加（每行字段已经是制表符分隔）
        printf '%s\n' "$data" >> "$output"
    else
        # 没有结果，补一行空值（run_accession 也空）
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "" "" "" "" "" "" "" "" "" "" "" "" >> "$output"
    fi
done < "$input"

echo "结果写在 $output"
