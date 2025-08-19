#!/bin/bash
unset http_proxy
unset https_proxy

echo "GNU Parallel版本 - Assembly信息提取脚本"

# 配置
INPUT_FILE="/mnt/d/迅雷下载/鲍曼组装/conf/sequence.seq"
OUTPUT_CSV="/mnt/d/迅雷下载/鲍曼组装/ncbi_refseq_assembly_mapping_gnu_parallel.csv"
LOG_FILE="/mnt/d/迅雷下载/鲍曼组装/assembly_extraction_log_gnu_parallel.txt"

# 并行配置
MAX_JOBS=4  # 最大并行任务数

# 检查GNU parallel是否可用
if ! command -v parallel &> /dev/null; then
    echo "错误: 需要安装 GNU parallel"
    echo "Ubuntu/Debian: sudo apt-get install parallel"
    echo "CentOS/RHEL: sudo yum install parallel 或 sudo dnf install parallel"
    echo "macOS: brew install parallel"
    exit 1
fi

# 初始化文件
echo "=== Assembly编号提取开始于 $(date) ===" | tee "$LOG_FILE"
echo "NCBI_RefSeq_Accession,Assembly_Accession,BioProject,BioSample,Organism,Status,Error_Message" > "$OUTPUT_CSV"

# 处理单个登录号的函数
process_single_accession() {
    local acc="$1"
    
    # 跳过空行
    [[ -z "$acc" ]] && return
    
    # 获取记录信息
    local record_info=""
    local temp_query="${acc}[accn]"
    
    if record_info=$(timeout 30s esearch -db nuccore -query "$temp_query" 2>/dev/null | timeout 30s efetch -format gb 2>/dev/null); then
        if [[ -n "$record_info" ]]; then
            # 提取信息
            local assembly_acc=$(echo "$record_info" | grep -E "Assembly:" | head -1 | sed 's/.*Assembly: *//' || echo "")
            local bioproject=$(echo "$record_info" | grep -E "BioProject:" | head -1 | sed 's/.*BioProject: *//' || echo "")
            local biosample=$(echo "$record_info" | grep -E "BioSample:" | head -1 | sed 's/.*BioSample: *//' || echo "")
            local organism=$(echo "$record_info" | grep -E "^  ORGANISM" | head -1 | sed 's/^  ORGANISM  //' || echo "")
            
            # 判断状态
            local status="Other"
            if echo "$record_info" | grep -qi "whole genome shotgun"; then
                status="WGS_Project"
            elif echo "$record_info" | grep -qi "complete genome"; then
                status="Complete_Genome"
            elif echo "$record_info" | grep -qi "chromosome"; then
                status="Chromosome"
            elif echo "$record_info" | grep -qi "plasmid"; then
                status="Plasmid"
            fi
            
            if [[ -n "$assembly_acc" ]]; then
                # 成功输出
                printf '"%s","%s","%s","%s","%s","%s",""\n' \
                    "$acc" "$assembly_acc" "$bioproject" "$biosample" "$organism" "$status"
                echo "$(date): SUCCESS - $acc -> $assembly_acc" >&2
            else
                # 未找到Assembly
                printf '"%s","","","","%s","No_Assembly","No Assembly found"\n' \
                    "$acc" "$organism"
                echo "$(date): NO_ASSEMBLY - $acc" >&2
            fi
        else
            # 空记录
            printf '"%s","","","","","Failed","Empty record"\n' "$acc"
            echo "$(date): EMPTY - $acc" >&2
        fi
    else
        # 获取失败
        printf '"%s","","","","","Failed","Fetch failed or timeout"\n' "$acc"
        echo "$(date): FAILED - $acc (fetch failed or timeout)" >&2
    fi
    
    # API限制延迟
    sleep 0.1
}

# 导出函数
export -f process_single_accession

# 读取总行数
total_lines=$(wc -l < "$INPUT_FILE")
echo "总共需要处理 $total_lines 个登录号"
echo "使用 GNU parallel，最大并行任务数: $MAX_JOBS"

start_time=$(date +%s)

# 使用GNU parallel处理
echo "开始并行处理..."
cat "$INPUT_FILE" | \
    parallel --will-cite --jobs "$MAX_JOBS" --bar --eta process_single_accession {} \
    2>> "$LOG_FILE" >> "$OUTPUT_CSV"

# 统计结果
total_count=$(tail -n +2 "$OUTPUT_CSV" | wc -l)
success_count=$(tail -n +2 "$OUTPUT_CSV" | cut -d',' -f2 | grep -v '^"*"*$' | grep -v '^""$' | wc -l)
failed_count=$((total_count - success_count))

# 最终统计
end_time=$(date +%s)
total_time=$(( end_time - start_time ))

echo ""
echo "=== GNU Parallel提取完成 ==="
echo "结束时间: $(date)"
echo "总耗时: $(( total_time / 60 )) 分钟 $(( total_time % 60 )) 秒"
echo ""
echo "总计处理: $total_count 个记录"
echo "成功提取: $success_count"
echo "失败: $failed_count"
if (( total_count > 0 )); then
    echo "成功率: $(( success_count * 100 / total_count ))%"
fi

if (( total_time > 0 )); then
    echo "平均处理速度: $(echo "scale=2; $total_count / ($total_time / 60)" | bc -l 2>/dev/null || echo "计算中") 记录/分钟"
fi

echo ""
echo "输出文件:"
echo "  CSV文件: $OUTPUT_CSV"
echo "  日志文件: $LOG_FILE"

# 显示结果预览
if [[ -f "$OUTPUT_CSV" ]]; then
    echo ""
    echo "结果预览:"
    head -6 "$OUTPUT_CSV"
    
    echo ""
    echo "成功的Assembly统计 (前10个):"
    tail -n +2 "$OUTPUT_CSV" | cut -d',' -f2 | grep -v '^"*"*$' | grep -v '^""$' | sort | uniq -c | sort -nr | head -10
fi

echo ""
echo "GNU Parallel任务完成！这是最高效的并行处理方案。"
