#!/bin/bash

DATA_DIR="/data_raid/7_luolintao/1_鲍曼/2-测序/data/"
OUT_DIR="${DATA_DIR}/FASTQ"
LOG_FILE="${DATA_DIR}/sra_conversion_simple.log"
PROGRESS_FILE="${DATA_DIR}/sra_progress.tmp"

# 设置并行处理的线程数
PARALLEL_JOBS=8

mkdir -p ${OUT_DIR}

# 清空日志文件和进度文件
echo "SRA to FASTQ conversion started at $(date)" > ${LOG_FILE}
echo "0" > ${PROGRESS_FILE}

# 获取所有SRA文件
sra_files=($(find ${DATA_DIR} -type f -name "*.sra"))
total_files=${#sra_files[@]}

echo "Found ${total_files} SRA files to process" >> ${LOG_FILE}
echo "Using ${PARALLEL_JOBS} parallel jobs" >> ${LOG_FILE}

# 进度条函数
show_progress() {
    local current=$1
    local total=$2
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
    
    # 检查是否已经存在输出文件
    if [[ -f "${OUT_DIR}/${basename}.sra_1.fastq" && -f "${OUT_DIR}/${basename}.sra_2.fastq" ]]; then
        echo "Skipping: $basename (already exists)" >> ${LOG_FILE}
        return 0
    fi
    
    echo "Processing: $sra_file" >> ${LOG_FILE}
    
    # 切换到输出目录并运行fasterq-dump
    if (cd "${OUT_DIR}" && fasterq-dump --split-files --threads 2 "$sra_file") 2>>${LOG_FILE}; then
        echo "Success: $basename" >> ${LOG_FILE}
        # 验证文件是否真的生成了
        if [[ -f "${OUT_DIR}/${basename}.sra_1.fastq" && -f "${OUT_DIR}/${basename}.sra_2.fastq" ]]; then
            echo "Verified: $basename files created successfully" >> ${LOG_FILE}
        else
            echo "Warning: $basename conversion reported success but files not found" >> ${LOG_FILE}
            # 检查是否生成了其他格式的文件名
            echo "Checking for alternative file names..." >> ${LOG_FILE}
            ls -la "${OUT_DIR}/${basename}"* 2>/dev/null >> ${LOG_FILE} || echo "No files found with basename ${basename}" >> ${LOG_FILE}
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
total_fastq=$(find ${OUT_DIR} -name "*.fastq" | wc -l)
total_samples=$((total_fastq / 2))
echo "Total FASTQ files: $total_fastq" >> ${LOG_FILE}
echo "Total samples processed: $total_samples" >> ${LOG_FILE}
echo "Final statistics: $total_fastq FASTQ files ($total_samples samples) generated"
