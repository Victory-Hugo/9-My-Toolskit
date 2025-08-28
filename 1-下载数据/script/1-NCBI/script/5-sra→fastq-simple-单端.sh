#!/bin/bash

# 定义目录
SRA_DIR="/data_raid/7_luolintao/1_Baoman/2-Sequence/"
FASTQ_DIR="${SRA_DIR}/FASTQ"

# 创建FASTQ目录
mkdir -p "${FASTQ_DIR}"

# 查找所有 .sra 文件并保存到列表
find "${SRA_DIR}" -type f -name "*.sra" > "${SRA_DIR}/sra_files.txt"

# 进入 FASTQ 输出目录
cd "${FASTQ_DIR}" || exit 1

# 使用 parallel 并行转换 SRA -> FASTQ
parallel --bar -j 16 fastq-dump --split-3 {} --gzip < "${SRA_DIR}/sra_files.txt"

echo "[所有 SRA 文件已成功转换为 FASTQ 格式并保存到 ${FASTQ_DIR}]"
