#!/usr/bin/env bash
set -euo pipefail

# 下载目录（末尾不加斜杠）  
DOWNLOAD_DIR="/mnt/d/迅雷下载/NCBI/PRJNA1028672/"

# 日志文件
LOG_FILE="${DOWNLOAD_DIR}/conversion.log"
touch "${LOG_FILE}"

# 查找所有 .sra
find "${DOWNLOAD_DIR}" -type f -name "*.sra" | while IFS= read -r sra_file; do
    base_name=$(basename "${sra_file}" .sra)
    fq1="${DOWNLOAD_DIR}/${base_name}_1.fastq.gz"
    fq2="${DOWNLOAD_DIR}/${base_name}_2.fastq.gz"

    # 如果两个输出都存在，说明已经转换完成，跳过
    if [[ -f "${fq1}" && -f "${fq2}" ]]; then
        echo "$(date '+%F %T') [SKIP] ${base_name} 已存在 ${base_name}_1.fastq.gz 和 ${base_name}_2.fastq.gz" \
            >> "${LOG_FILE}"
        continue
    fi

    # 如果只存在部分输出，先删除残留输出，保证重跑干净
    if [[ -f "${fq1}" || -f "${fq2}" ]]; then
        echo "$(date '+%F %T') [CLEANUP] ${base_name} 检测到残留 fastq，正在移除" \
            >> "${LOG_FILE}"
        rm -f "${fq1}" "${fq2}"
    fi

    # 开始转换
    echo "$(date '+%F %T') [START] 转换 ${base_name}.sra → fastq" \
        >> "${LOG_FILE}"
    if fastq-dump --split-files --gzip "${sra_file}" -O "${DOWNLOAD_DIR}"; then
        echo "$(date '+%F %T') [OK]   ${base_name}.sra 转换完成" \
            >> "${LOG_FILE}"

        # 删除中间文件（.sra）
        rm -f "${sra_file}"
        echo "$(date '+%F %T') [DEL]  删除 ${base_name}.sra" \
            >> "${LOG_FILE}"
    else
        echo "$(date '+%F %T') [FAIL] ${base_name}.sra 转换失败，保留原文件以便重试" \
            >> "${LOG_FILE}"
    fi
done

#* ====================版本二=========================
#* 使用了更先进的并行压缩和日志记录方式，适合大规模数据转换
# #!/usr/bin/env bash
# set -euo pipefail

# # 下载目录（末尾不加斜杠）
# DOWNLOAD_DIR="/mnt/d/迅雷下载/NCBI"

# # 日志文件
# LOG_FILE="${DOWNLOAD_DIR}/conversion.log"
# touch "${LOG_FILE}"

# # 并行压缩线程数（根据机器核数调整）
# THREADS=8

# # 压缩命令：优先 pigz，否则 fallback 到 gzip
# if command -v pigz &>/dev/null; then
#     COMPRESS_CMD="pigz -p ${THREADS}"
# else
#     COMPRESS_CMD="gzip"
# fi

# find "${DOWNLOAD_DIR}" -type f -name "*.sra" | while IFS= read -r sra_file; do
#     base_name=$(basename "${sra_file}" .sra)
#     raw1="${DOWNLOAD_DIR}/${base_name}_1.fastq"
#     raw2="${DOWNLOAD_DIR}/${base_name}_2.fastq"
#     gz1="${raw1}.gz"
#     gz2="${raw2}.gz"

#     # 已完成则跳过
#     if [[ -f "${gz1}" && -f "${gz2}" ]]; then
#         echo "$(date '+%F %T') [SKIP] ${base_name} 已存在 gzipped FASTQ" \
#             >> "${LOG_FILE}"
#         continue
#     fi

#     # 部分残留则清理
#     if [[ -f "${raw1}" || -f "${raw2}" || -f "${gz1}" || -f "${gz2}" ]]; then
#         echo "$(date '+%F %T') [CLEANUP] ${base_name} 检测到残留文件，正在移除" \
#             >> "${LOG_FILE}"
#         rm -f "${raw1}" "${raw2}" "${gz1}" "${gz2}"
#     fi

#     # 开始转换
#     echo "$(date '+%F %T') [START] ${base_name}.sra → FASTQ" \
#         >> "${LOG_FILE}"
#     if fasterq-dump --split-files --threads "${THREADS}" --outdir "${DOWNLOAD_DIR}" "${sra_file}"; then
#         echo "$(date '+%F %T') [OK]    ${base_name}.sra 转换完成" \
#             >> "${LOG_FILE}"

#         # 压缩 FASTQ
#         echo "$(date '+%F %T') [COMPRESS] 对 ${base_name}_*.fastq 进行 gzip" \
#             >> "${LOG_FILE}"
#         ${COMPRESS_CMD} "${raw1}" "${raw2}"

#         # 删除原 .sra
#         rm -f "${sra_file}"
#         echo "$(date '+%F %T') [DEL]    删除 ${base_name}.sra" \
#             >> "${LOG_FILE}"
#     else
#         echo "$(date '+%F %T') [FAIL]  ${base_name}.sra 转换失败，保留原文件以便重试" \
#             >> "${LOG_FILE}"
#     fi
# done
