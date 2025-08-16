#!/bin/bash
PROJ="PRJNA1028672"
INPUT="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/conf/${PROJ}_runinfo.csv"
OUTPUT="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/conf/${PROJ}_下载NCBI.txt"

awk -F'\t' 'BEGIN{OFS=""; sep=","}
NR==1{
    if(index($0, OFS) == 0) FS=","; # 自动判断分隔符
    for(i=1;i<=NF;i++) if($i=="AssemblyAccession") col=i;
    next
}
{print $col}' \
"$INPUT" \
> "$OUTPUT"

#TODO 下一步使用1-下载数据/script/1-NCBI/script/5-NCBI-Assembly-download.sh