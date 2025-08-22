# #!/usr/bin/env bash

# set -euo pipefail

# # 下载目录（末尾不加斜杠）  
# DOWNLOAD_DIR="/mnt/c/Users/Administrator/Desktop/ERR197551/"

# # 日志文件
# LOG_FILE="${DOWNLOAD_DIR}/conversion.log"
# touch "${LOG_FILE}"

# # 查找所有 .sra
# find "${DOWNLOAD_DIR}" -type f -name "*.sra" | while IFS= read -r sra_file; do
#     base_name=$(basename "${sra_file}" .sra)
#     fq1="${DOWNLOAD_DIR}/${base_name}_1.fastq.gz"
#     fq2="${DOWNLOAD_DIR}/${base_name}_2.fastq.gz"

#     # 如果两个输出都存在，说明已经转换完成，跳过
#     if [[ -f "${fq1}" && -f "${fq2}" ]]; then
#         echo "$(date '+%F %T') [SKIP] ${base_name} 已存在 ${base_name}_1.fastq.gz 和 ${base_name}_2.fastq.gz" \
#             >> "${LOG_FILE}"
#         continue
#     fi

#     # 如果只存在部分输出，先删除残留输出，保证重跑干净
#     if [[ -f "${fq1}" || -f "${fq2}" ]]; then
#         echo "$(date '+%F %T') [CLEANUP] ${base_name} 检测到残留 fastq，正在移除" \
#             >> "${LOG_FILE}"
#         rm -f "${fq1}" "${fq2}"
#     fi

#     # 开始转换
#     echo "$(date '+%F %T') [START] 转换 ${base_name}.sra → fastq" \
#         >> "${LOG_FILE}"
#     if fastq-dump --split-files --gzip "${sra_file}" -O "${DOWNLOAD_DIR}"; then
#         echo "$(date '+%F %T') [OK]   ${base_name}.sra 转换完成" \
#             >> "${LOG_FILE}"

#         # 删除中间文件（.sra）
#         rm -f "${sra_file}"
#         echo "$(date '+%F %T') [DEL]  删除 ${base_name}.sra" \
#             >> "${LOG_FILE}"
#     else
#         echo "$(date '+%F %T') [FAIL] ${base_name}.sra 转换失败，保留原文件以便重试" \
#             >> "${LOG_FILE}"
#     fi
# done

#!/usr/bin/env bash
# ====================版本二=========================
# 使用了更先进的并行压缩和日志记录方式，适合大规模数据转换

set -euo pipefail


# 下载目录（末尾不加斜杠）
DOWNLOAD_DIR="/mnt/c/Users/Administrator/Desktop/ERR4766511/"

# 日志文件
LOG_FILE="${DOWNLOAD_DIR}/conversion.log"
touch "${LOG_FILE}"

# 并行压缩线程数（根据机器核数调整）
# 自动检测CPU核心数，但限制最大值避免过度使用
CPU_CORES=$(nproc)
THREADS=$((CPU_CORES > 16 ? 16 : CPU_CORES))

# 压缩模式选择：
# "ultrafast" - 极速模式，最低压缩级别，几乎不压缩但很快
# "fast" - 最快速度，压缩级别1
# "balanced" - 平衡模式，压缩级别3
# "best" - 最佳压缩，压缩级别6
# "no" - 不压缩，保留原始fastq文件
COMPRESS_MODE="fast"

case "${COMPRESS_MODE}" in
    "ultrafast")
        COMPRESS_LEVEL=1
        # 对于极速模式，使用最快的 pigz 设置
        if command -v pigz &>/dev/null; then
            COMPRESS_CMD="pigz -p ${THREADS} -1 --fast"
        else
            COMPRESS_CMD="gzip -1"
        fi
        ;;
    "fast")
        COMPRESS_LEVEL=1
        ;;
    "balanced")
        COMPRESS_LEVEL=3
        ;;
    "best")
        COMPRESS_LEVEL=6
        ;;
    "no")
        COMPRESS_LEVEL=""
        ;;
    *)
        COMPRESS_LEVEL=3
        ;;
esac

# 压缩命令：优先 pigz，否则 fallback 到 gzip（除非是 ultrafast 模式已经设置）
if [[ "${COMPRESS_MODE}" != "ultrafast" ]] && command -v pigz &>/dev/null && [[ "${COMPRESS_MODE}" != "no" ]]; then
    COMPRESS_CMD="pigz -p ${THREADS} -${COMPRESS_LEVEL}"
elif [[ "${COMPRESS_MODE}" != "ultrafast" ]] && [[ "${COMPRESS_MODE}" != "no" ]]; then
    COMPRESS_CMD="gzip -${COMPRESS_LEVEL}"
elif [[ "${COMPRESS_MODE}" == "no" ]]; then
    COMPRESS_CMD=""
fi

# 递归查找所有 .sra 文件（包括子目录）
find "${DOWNLOAD_DIR}" -type f -name "*.sra" | while IFS= read -r sra_file; do
    base_name=$(basename "${sra_file}" .sra)
    sra_dir=$(dirname "${sra_file}")
    # fasterq-dump 有时会生成 .f 扩展名而不是 .fastq
    raw1_f="${sra_dir}/${base_name}_1.f"
    raw2_f="${sra_dir}/${base_name}_2.f"
    raw1="${sra_dir}/${base_name}_1.fastq"
    raw2="${sra_dir}/${base_name}_2.fastq"
    gz1="${raw1}.gz"
    gz2="${raw2}.gz"

    # 已完成则跳过（根据压缩模式调整判断逻辑）
    if [[ "${COMPRESS_MODE}" == "no" ]]; then
        # 不压缩模式：检查原始 fastq 文件
        if [[ -f "${raw1}" && -f "${raw2}" ]]; then
            echo "$(date '+%F %T') [SKIP] ${base_name} 已存在 FASTQ 文件" \
                >> "${LOG_FILE}"
            continue
        fi
    else
        # 压缩模式：检查压缩文件
        if [[ -f "${gz1}" && -f "${gz2}" ]]; then
            echo "$(date '+%F %T') [SKIP] ${base_name} 已存在 gzipped FASTQ" \
                >> "${LOG_FILE}"
            continue
        fi
    fi

    # 部分残留则清理
    if [[ -f "${raw1}" || -f "${raw2}" || -f "${raw1_f}" || -f "${raw2_f}" || -f "${gz1}" || -f "${gz2}" ]]; then
        echo "$(date '+%F %T') [CLEANUP] ${base_name} 检测到残留文件，正在移除" \
            >> "${LOG_FILE}"
        rm -f "${raw1}" "${raw2}" "${raw1_f}" "${raw2_f}" "${gz1}" "${gz2}"
    fi

    # 开始转换
    echo "$(date '+%F %T') [START] ${base_name}.sra → FASTQ" \
        >> "${LOG_FILE}"
    if fasterq-dump-orig.3.1.1 --split-files --threads "${THREADS}" --outdir "${sra_dir}" "${sra_file}"; then
        echo "$(date '+%F %T') [OK]    ${base_name}.sra 转换完成" \
            >> "${LOG_FILE}"

        # 重命名 .f 文件为 .fastq（如果需要）
        if [[ -f "${raw1_f}" && -f "${raw2_f}" ]]; then
            mv "${raw1_f}" "${raw1}"
            mv "${raw2_f}" "${raw2}"
            echo "$(date '+%F %T') [RENAME] 重命名 .f 为 .fastq" \
                >> "${LOG_FILE}"
        fi

        # 压缩或保留 FASTQ 文件
        if [[ "${COMPRESS_MODE}" != "no" ]]; then
            echo "$(date '+%F %T') [COMPRESS] 对 ${base_name}_*.fastq 进行${COMPRESS_MODE}模式压缩" \
                >> "${LOG_FILE}"
            
            # 并行压缩两个文件，提升速度
            {
                ${COMPRESS_CMD} "${raw1}" &
                ${COMPRESS_CMD} "${raw2}" &
                wait  # 等待两个压缩任务完成
            }
        else
            echo "$(date '+%F %T') [SKIP-COMPRESS] 保留原始 FASTQ 文件" \
                >> "${LOG_FILE}"
        fi

        # 删除原 .sra
        # rm -f "${sra_file}"
        # echo "$(date '+%F %T') [DEL]    删除 ${base_name}.sra" \
            # >> "${LOG_FILE}"
    else
        echo "$(date '+%F %T') [FAIL]  ${base_name}.sra 转换失败，保留原文件以便重试" \
            >> "${LOG_FILE}"
    fi
done
