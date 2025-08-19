#!/bin/bash
unset http_proxy
unset https_proxy

echo "最终版本 - Assembly信息提取脚本"

# 配置
INPUT_FILE="/mnt/d/迅雷下载/鲍曼组装/conf/sequence.seq"
OUTPUT_CSV="/mnt/d/迅雷下载/鲍曼组装/ncbi_refseq_assembly_mapping.csv"
LOG_FILE="/mnt/d/迅雷下载/鲍曼组装/assembly_extraction_log.txt"

# 初始化文件
echo "=== Assembly编号提取开始于 $(date) ===" | tee "$LOG_FILE"
echo "NCBI_RefSeq_Accession,Assembly_Accession,BioProject,BioSample,Organism,Status,Error_Message" > "$OUTPUT_CSV"

# 统计
total_count=0
success_count=0
failed_count=0

# 读取所有登录号到数组中（避免stdin冲突）
echo "读取所有登录号..."
mapfile -t accessions < "$INPUT_FILE"

total_lines=${#accessions[@]}
echo "总共需要处理 $total_lines 个登录号"

start_time=$(date +%s)

# 处理每个登录号
for i in "${!accessions[@]}"; do
    acc="${accessions[i]}"
    
    # 跳过空行
    [[ -z "$acc" ]] && continue
    
    total_count=$((total_count + 1))
    current_num=$((i + 1))
    
    echo ""
    echo "[$current_num/$total_lines] 处理: $acc"
    
    # 获取记录信息，使用更稳定的方法
    record_info=""
    temp_query="${acc}[accn]"
    if record_info=$(esearch -db nuccore -query "$temp_query" 2>/dev/null | efetch -format gb 2>/dev/null); then
        if [[ -n "$record_info" ]]; then
            echo "  -> ✓ 成功获取记录信息"
            
            # 提取信息
            assembly_acc=$(echo "$record_info" | grep -E "Assembly:" | head -1 | sed 's/.*Assembly: *//' || echo "")
            bioproject=$(echo "$record_info" | grep -E "BioProject:" | head -1 | sed 's/.*BioProject: *//' || echo "")
            biosample=$(echo "$record_info" | grep -E "BioSample:" | head -1 | sed 's/.*BioSample: *//' || echo "")
            organism=$(echo "$record_info" | grep -E "^  ORGANISM" | head -1 | sed 's/^  ORGANISM  //' || echo "")
            
            # 判断状态
            status="Other"
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
                echo "  -> Assembly: $assembly_acc"
                echo "  -> BioProject: $bioproject"
                echo "  -> BioSample: $biosample"
                echo "  -> Organism: $organism"
                echo "  -> Status: $status"
                
                # 写入CSV
                printf '"%s","%s","%s","%s","%s","%s",""\n' \
                    "$acc" "$assembly_acc" "$bioproject" "$biosample" "$organism" "$status" >> "$OUTPUT_CSV"
                
                success_count=$((success_count + 1))
                echo "$(date): SUCCESS - $acc -> $assembly_acc" >> "$LOG_FILE"
            else
                echo "  -> ✗ 未找到Assembly编号"
                printf '"%s","","","","%s","No_Assembly","No Assembly found"\n' \
                    "$acc" "$organism" >> "$OUTPUT_CSV"
                failed_count=$((failed_count + 1))
                echo "$(date): NO_ASSEMBLY - $acc" >> "$LOG_FILE"
            fi
        else
            echo "  -> ✗ 获取的记录为空"
            printf '"%s","","","","","Failed","Empty record"\n' "$acc" >> "$OUTPUT_CSV"
            failed_count=$((failed_count + 1))
            echo "$(date): EMPTY - $acc" >> "$LOG_FILE"
        fi
    else
        echo "  -> ✗ 无法获取记录信息"
        printf '"%s","","","","","Failed","Fetch failed"\n' "$acc" >> "$OUTPUT_CSV"
        failed_count=$((failed_count + 1))
        echo "$(date): FAILED - $acc (fetch failed)" >> "$LOG_FILE"
    fi
    
    # 显示进度
    if (( total_count % 10 == 0 )) || (( current_num == total_lines )); then
        echo ""
        echo "=== 进度报告 ==="
        echo "已处理: $current_num/$total_lines ($(( current_num * 100 / total_lines ))%)"
        echo "成功: $success_count, 失败: $failed_count"
        
        # 计算预计剩余时间
        elapsed_time=$(( $(date +%s) - start_time ))
        if (( current_num > 0 )); then
            avg_time_per_record=$(( elapsed_time / current_num ))
            remaining_records=$(( total_lines - current_num ))
            estimated_remaining=$(( remaining_records * avg_time_per_record ))
            echo "已用时: $(( elapsed_time / 60 ))分$(( elapsed_time % 60 ))秒"
            echo "预计剩余: $(( estimated_remaining / 60 ))分$(( estimated_remaining % 60 ))秒"
        fi
        echo "==============="
        echo ""
    fi
    
    # API限制延迟
    sleep 0.1
done

# 最终统计
end_time=$(date +%s)
total_time=$(( end_time - start_time ))

echo ""
echo "=== 提取完成 ==="
echo "结束时间: $(date)"
echo "总耗时: $(( total_time / 60 )) 分钟 $(( total_time % 60 )) 秒"
echo ""
echo "总计处理: $total_count 个记录"
echo "成功提取: $success_count"
echo "失败: $failed_count"
if (( total_count > 0 )); then
    echo "成功率: $(( success_count * 100 / total_count ))%"
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
echo "任务完成！您现在有了一个包含所有NCBI Reference Sequence对应Assembly编号的CSV文件。"
