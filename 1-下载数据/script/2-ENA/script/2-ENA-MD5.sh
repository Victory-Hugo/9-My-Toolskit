#!/bin/bash
set -euo pipefail

# 输入输出（路径里有空格/特殊字符，注意用引号）
INPUT="/mnt/f/OneDrive/文档（共享）/4_古代DNA/SAMEA_aDNA.txt"
OUTPUT="/mnt/f/OneDrive/文档（共享）/4_古代DNA/SAMEA_aDNA_MD5.txt"

# 要的字段：包含 fastq_md5 和对应的 fastq_ftp
FIELDS="run_accession,sample_accession,experiment_accession,study_accession,tax_id,scientific_name,base_count,fastq_ftp,fastq_md5"

# 写表头（和 API 输出一致，用制表符分隔）
echo -e "run_accession\tsample_accession\texperiment_accession\tstudy_accession\ttax_id\tscientific_name\tbase_count\tfastq_ftp\tfastq_md5" > "$OUTPUT"

while IFS= read -r acc; do
    # 跳过空行和注释
    [[ -z "${acc// /}" || "${acc:0:1}" == "#" ]] && continue
    # 去除回车和首尾空白
    acc=$(echo "$acc" | tr -d '\r' | awk '{$1=$1};1')

    echo "处理 $acc" >&2

    # 调用 ENA API
    resp=$(curl -s "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${acc}&result=read_run&fields=${FIELDS}&format=tsv")

    # 取除表头的内容（可能有多行：一个 sample 可能对应多个 run）
    data=$(printf '%s\n' "$resp" | awk 'NR>1')

    if [[ -n "$data" ]]; then
        # 追加到输出（保持原有字段顺序）
        printf '%s\n' "$data" >> "$OUTPUT"
    else
        # 没有结果时补一行空字段（保留 sample 信息在 sample_accession 位置）
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "" "$acc" "" "" "" "" "" "" "" >> "$OUTPUT"
    fi
done < "$INPUT"

echo "完成，结果写在：$OUTPUT"
