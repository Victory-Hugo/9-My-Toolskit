: '
脚本功能：
    该脚本用于根据输入文件（每行一个 ERS 编号）批量查询 ENA 数据库，获取指定字段的全部信息，并输出为 TSV 文件。

使用说明：
    1. 输入文件（input）应为每行一个 ERS 编号（如 ERS2540882），可包含注释（以 # 开头）和空行。
    2. 输出文件（output）为带表头的 TSV 文件，包含每个 ERS 编号对应的 run 信息。
    3. 查询字段可在 FIELDS 变量中自定义。
    4. 若某个 ERS 编号无结果，则输出一行空字段以占位。

主要流程：
    - 读取输入文件，逐行处理每个 ERS 编号。
    - 跳过空行和注释行，自动去除行首尾空白字符。
    - 通过 curl 请求 ENA API，获取指定字段的 TSV 数据。
    - 结果追加到输出文件，若无结果则补一行空值。
    - 最终输出文件包含所有 ERS 编号的查询结果。

注意事项：
    - 需保证网络畅通以访问 ENA API。
    - 输出文件会被覆盖，请提前备份重要数据。
'
#!/bin/bash
set -euo pipefail

input="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf/ERS.txt"     # 每行一个 ERS2540882 形式
output="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf/ENA_full.tsv"

# 要的字段列表
FIELDS="run_accession,sample_accession,experiment_accession,study_accession,tax_id,scientific_name,base_count,fastq_ftp,fastq_md5,sra_ftp,bam_ftp,bam_bytes,bam_md5"

# 写表头（和 API 返回一致）
echo -e "run_accession\tsample_accession\texperiment_accession\tstudy_accession\ttax_id\tscientific_name\tbase_count\tfastq_ftp\tfastq_md5\tsra_ftp\tbam_ftp\tbam_bytes\tbam_md5" > "$output"

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
