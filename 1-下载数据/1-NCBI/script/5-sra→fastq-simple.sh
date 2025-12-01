#!/bin/bash

DATA_DIR="/data_raid/7_luolintao/1_Baoman/2-Sequence/FASTQ/鲍曼NC2025_1/DRR033185/"
OUT_DIR="${DATA_DIR}/FASTQ"
LOG_FILE="${DATA_DIR}/sra_conversion_simple.log"
PROGRESS_FILE="${DATA_DIR}/sra_progress.tmp"

# 设置并行处理的线程数
PARALLEL_JOBS=1

mkdir -p ${OUT_DIR}

# 清空日志文件和进度文件
echo "SRA to FASTQ conversion started at $(date)" > ${LOG_FILE}
echo "0" > ${PROGRESS_FILE}

# 获取所有SRA文件
sra_files=($(find ${DATA_DIR} -type f -name "*.sra"))
total_files=${#sra_files[@]}

echo "Found ${total_files} SRA files to process" >> ${LOG_FILE}
echo "Using ${PARALLEL_JOBS} parallel jobs" >> ${LOG_FILE}

# 检查是否找到SRA文件
if [ ${total_files} -eq 0 ]; then
    echo "No SRA files found in ${DATA_DIR}"
    echo "No SRA files found in ${DATA_DIR}" >> ${LOG_FILE}
    echo "Please check if the DATA_DIR path is correct and contains .sra files"
    echo "SRA to FASTQ conversion completed at $(date) - No files to process" >> ${LOG_FILE}
    exit 0
fi

# 进度条函数
show_progress() {
    local current=$1
    local total=$2
    
    # 防止除以0错误
    if [ $total -eq 0 ]; then
        printf "\rProgress: [--------------------------------------------------] 0%% (0/0)"
        return
    fi
    
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\rProgress: ["
    printf "%*s" $filled | tr ' ' '='
    printf "%*s" $empty | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percent $current $total
}

# 处理单个SRA文件的函数
process_sra() {
    local sra_file="$1"
    local basename=$(basename "$sra_file" .sra)
    
    # 检查是否已经存在压缩后的输出文件
    if [[ -f "${OUT_DIR}/${basename}.sra_1.fastq.gz" && -f "${OUT_DIR}/${basename}.sra_2.fastq.gz" ]]; then
        echo "Skipping: $basename (compressed files already exist)" >> ${LOG_FILE}
        return 0
    fi
    
    # 检查是否存在未压缩的文件（可能之前的运行被中断）
    if [[ -f "${OUT_DIR}/${basename}.sra_1.fastq" && -f "${OUT_DIR}/${basename}.sra_2.fastq" ]]; then
        echo "Found uncompressed files for $basename, compressing..." >> ${LOG_FILE}
        # 压缩现有文件
        if gzip "${OUT_DIR}/${basename}.sra_1.fastq" "${OUT_DIR}/${basename}.sra_2.fastq" 2>>${LOG_FILE}; then
            echo "Compression successful: $basename" >> ${LOG_FILE}
            return 0
        else
            echo "Compression failed: $basename" >> ${LOG_FILE}
            return 1
        fi
    fi
    
    echo "Processing: $sra_file" >> ${LOG_FILE}
    
    # 切换到输出目录并运行fasterq-dump
    if (cd "${OUT_DIR}" && fasterq-dump --split-files --threads 8 "$sra_file") 2>>${LOG_FILE}; then
        echo "FASTQ generation success: $basename" >> ${LOG_FILE}
        # 验证文件是否真的生成了
        if [[ -f "${OUT_DIR}/${basename}.sra_1.fastq" && -f "${OUT_DIR}/${basename}.sra_2.fastq" ]]; then
            echo "Verified: $basename FASTQ files created successfully" >> ${LOG_FILE}
            
            # 压缩生成的FASTQ文件
            echo "Compressing: $basename" >> ${LOG_FILE}
            if gzip "${OUT_DIR}/${basename}.sra_1.fastq" "${OUT_DIR}/${basename}.sra_2.fastq" 2>>${LOG_FILE}; then
                echo "Compression successful: $basename -> .gz files created and .fastq files removed" >> ${LOG_FILE}
                
                # 验证压缩文件是否存在
                if [[ -f "${OUT_DIR}/${basename}.sra_1.fastq.gz" && -f "${OUT_DIR}/${basename}.sra_2.fastq.gz" ]]; then
                    echo "Final verification successful: $basename .gz files exist" >> ${LOG_FILE}
                else
                    echo "Error: $basename .gz files not found after compression" >> ${LOG_FILE}
                    return 1
                fi
            else
                echo "Compression failed: $basename (keeping .fastq files)" >> ${LOG_FILE}
                return 1
            fi
        else
            echo "Warning: $basename conversion reported success but files not found" >> ${LOG_FILE}
            # 检查是否生成了其他格式的文件名
            echo "Checking for alternative file names..." >> ${LOG_FILE}
            ls -la "${OUT_DIR}/${basename}"* 2>/dev/null >> ${LOG_FILE} || echo "No files found with basename ${basename}" >> ${LOG_FILE}
            return 1
        fi
        return 0
    else
        echo "Failed: $basename" >> ${LOG_FILE}
        return 1
    fi
}

# 更新进度的函数
update_progress() {
    local current_count=$(cat ${PROGRESS_FILE})
    current_count=$((current_count + 1))
    echo $current_count > ${PROGRESS_FILE}
    show_progress $current_count $total_files
}

# 导出函数以便parallel使用
export -f process_sra update_progress show_progress
export DATA_DIR OUT_DIR LOG_FILE PROGRESS_FILE total_files

# 使用GNU parallel进行并行处理
if command -v parallel >/dev/null 2>&1; then
    echo "Using GNU parallel for processing..." >> ${LOG_FILE}
    
    # 显示初始进度条
    show_progress 0 $total_files
    
    # 并行处理，每完成一个任务就更新进度
    printf '%s\n' "${sra_files[@]}" | parallel -j${PARALLEL_JOBS} --line-buffer \
        'process_sra {} && update_progress' 2>>${LOG_FILE}
    
    echo  # 换行
else
    echo "GNU parallel not found, falling back to background processing..." >> ${LOG_FILE}
    
    # 如果没有parallel，使用后台进程进行并行处理
    current=0
    show_progress $current $total_files
    
    for sra_file in "${sra_files[@]}"; do
        # 启动后台进程
        (process_sra "$sra_file" && {
            # 原子操作更新进度
            (
                flock -x 200
                local current_count=$(cat ${PROGRESS_FILE})
                current_count=$((current_count + 1))
                echo $current_count > ${PROGRESS_FILE}
                show_progress $current_count $total_files
            ) 200>/tmp/progress.lock
        }) &
        
        # 控制并行进程数
        if (( $(jobs -r | wc -l) >= PARALLEL_JOBS )); then
            wait -n  # 等待任意一个后台进程完成
        fi
    done
    
    wait  # 等待所有后台进程完成
    echo  # 换行
fi

# 清理临时文件
rm -f ${PROGRESS_FILE}

echo "SRA to FASTQ conversion completed at $(date)" >> ${LOG_FILE}

# 显示最终统计
total_fastq_gz=$(find ${OUT_DIR} -name "*.fastq.gz" | wc -l)
total_fastq_uncompressed=$(find ${OUT_DIR} -name "*.fastq" | wc -l)
total_samples=$((total_fastq_gz / 2))
echo "Total compressed FASTQ files: $total_fastq_gz" >> ${LOG_FILE}
echo "Total uncompressed FASTQ files: $total_fastq_uncompressed" >> ${LOG_FILE}
echo "Total samples processed: $total_samples" >> ${LOG_FILE}
echo "Final statistics: $total_fastq_gz compressed FASTQ files ($total_samples samples) generated"
if [ $total_fastq_uncompressed -gt 0 ]; then
    echo "Warning: $total_fastq_uncompressed uncompressed FASTQ files remain (possible compression failures)"
fi
