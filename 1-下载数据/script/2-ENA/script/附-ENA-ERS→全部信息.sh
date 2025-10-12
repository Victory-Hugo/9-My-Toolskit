: '
脚本功能：
    该脚本用于根据输入文件（每行一个 ERS 编号）批量查询 ENA 数据库，获取指定字段的全部信息，并输出为 TSV 文件。
    支持并行处理、断点续传和失败重试机制。

使用说明：
    1. 输入文件（input）应为每行一个 ERS 编号（如 ERS2540882），可包含注释（以 # 开头）和空行。
    2. 输出文件（output）为带表头的 TSV 文件，包含每个 ERS 编号对应的 run 信息。
    3. 查询字段可在 FIELDS 变量中自定义。
    4. 若某个 ERS 编号无结果，则输出一行空字段以占位。
    5. 支持断点续传，如果脚本意外中断，再次运行会跳过已处理的条目。
    6. 每个失败的请求会重试最多3次，失败的条目会记录到日志文件。

主要流程：
    - 读取输入文件，逐行处理每个 ERS 编号。
    - 跳过空行、注释行和已处理的条目，自动去除行首尾空白字符。
    - 使用并行处理提高效率，默认并发数为8。
    - 通过 curl 请求 ENA API，获取指定字段的 TSV 数据。
    - 失败请求自动重试最多3次，支持指数退避。
    - 结果追加到输出文件，若无结果则补一行空值。
    - 最终输出文件包含所有 ERS 编号的查询结果。

注意事项：
    - 需保证网络畅通以访问 ENA API。
    - 输出文件支持断点续传，不会覆盖已有数据。
    - 失败日志保存在 .failed.log 文件中。
'
#!/bin/bash
set -euo pipefail

# 配置参数
input="/mnt/d/迅雷下载/古代DNA/补充下载/ERR.txt"     # 每行一个 SRR/ERR/DRR 或 ERS 编号
output="/mnt/d/迅雷下载/古代DNA/补充下载/ERR.tsv"
progress_file="${output}.progress"                   # 进度文件
failed_log="${output}.failed.log"                   # 失败日志
temp_dir="/tmp/ena_query_$$"                        # 临时目录
max_jobs=8                                           # 并发数
max_retries=3                                        # 最大重试次数

# 要的字段列表
FIELDS="run_accession,sample_accession,sample_alias,study_title,experiment_accession,study_accession,tax_id,scientific_name,base_count,fastq_ftp,fastq_md5"

# 创建临时目录
# mkdir -p "$temp_dir"
# trap "rm -rf $temp_dir" EXIT

# 文件锁初始化
touch "$output.lock"

# 初始化输出文件（如果不存在）
if [[ ! -f "$output" ]]; then
    echo -e "run_accession\tsample_accession\tsample_alias\tstudy_title\texperiment_accession\tstudy_accession\ttax_id\tscientific_name\tbase_count\tfastq_ftp\tfastq_md5" > "$output"
fi

# 初始化进度文件
[[ ! -f "$progress_file" ]] && touch "$progress_file"

# 查询单个编号的函数
query_accession() {
    local accession="$1"
    local retry_count=0
    
    # 判断编号类型并构建相应的查询URL
    local query_url
    if [[ "$accession" =~ ^[SED]RR[0-9]+ ]]; then
        # SRR/ERR/DRR编号 - 这是run编号
        query_url="https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${accession}&result=read_run&fields=${FIELDS}&format=tsv"
    elif [[ "$accession" =~ ^[SED]RS[0-9]+ ]]; then
        # SRS/ERS/DRS编号 - 这是sample编号
        query_url="https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${accession}&result=read_run&fields=${FIELDS}&format=tsv"
    else
        echo "✗ 不支持的编号格式: $accession" >&2
        # 写入空行
        (
            flock -x 200
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "" "" "" "" "" "" "" "" "" "" "" >> "$output"
            echo "$accession" >> "$progress_file"
        ) 200>"$output.lock"
        return 1
    fi
    
    while [[ $retry_count -lt $max_retries ]]; do
        echo "正在处理 $accession (尝试 $((retry_count + 1))/$max_retries)" >&2
        
        # 请求 ENA filereport，设置超时和重试参数
        if resp=$(curl -s --connect-timeout 30 --max-time 60 --retry 2 \
                      "$query_url" 2>/dev/null); then
            
            # 取除表头后的内容（如果有多个 run 会有多行）
            data=$(printf '%s\n' "$resp" | awk 'NR>1')
            
            if [[ -n "$data" ]]; then
                # 成功获取数据，使用文件锁写入
                (
                    flock -x 200
                    printf '%s\n' "$data" >> "$output"
                    echo "$accession" >> "$progress_file"
                ) 200>"$output.lock"
                echo "✓ 成功处理 $accession" >&2
                return 0
            elif [[ $(printf '%s\n' "$resp" | wc -l) -eq 1 ]]; then
                # 只有表头，说明没有数据，但请求成功
                (
                    flock -x 200
                    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "" "" "" "" "" "" "" "" "" "" "" >> "$output"
                    echo "$accession" >> "$progress_file"
                ) 200>"$output.lock"
                echo "✓ 成功处理 $accession (无数据)" >&2
                return 0
            fi
        fi
        
        # 失败，增加重试计数
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            # 指数退避：等待时间随重试次数增加
            sleep_time=$((retry_count * retry_count))
            echo "✗ $accession 请求失败，${sleep_time}秒后重试..." >&2
            sleep $sleep_time
        fi
    done
    
    # 所有重试都失败
    echo "✗ $accession 处理失败，已重试 $max_retries 次" >&2
    (
        flock -x 200
        echo "$(date '+%Y-%m-%d %H:%M:%S') $accession" >> "$failed_log"
        # 仍然写入空行以保持一致性
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "" "" "" "" "" "" "" "" "" "" "" >> "$output"
        echo "$accession" >> "$progress_file"
    ) 200>"$output.lock"
    return 1
}

# 收集未处理的编号
pending_accessions=()
while IFS= read -r accession; do
    # 跳过空行和注释
    [[ -z "${accession// /}" || "${accession:0:1}" == "#" ]] && continue
    accession=$(echo "$accession" | tr -d '\r' | awk '{$1=$1};1')  # trim
    
    # 检查是否已处理
    if ! grep -Fxq "$accession" "$progress_file" 2>/dev/null; then
        pending_accessions+=("$accession")
    else
        echo "⏭ 跳过已处理的 $accession" >&2
    fi
done < "$input"

echo "发现 ${#pending_accessions[@]} 个待处理的编号，开始并行处理..." >&2

# 并行处理函数
process_batch() {
    local batch_accessions=("$@")
    local pids=()
    
    for accession in "${batch_accessions[@]}"; do
        # 控制并发数
        while [[ ${#pids[@]} -ge $max_jobs ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[i]}" 2>/dev/null; then
                    unset pids[i]
                fi
            done
            pids=("${pids[@]}")  # 重新索引数组
            [[ ${#pids[@]} -ge $max_jobs ]] && sleep 0.1
        done
        
        # 启动新的查询进程
        query_accession "$accession" &
        pids+=($!)
    done
    
    # 等待所有进程完成
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done
}

# 分批处理所有待处理的编号
if [[ ${#pending_accessions[@]} -gt 0 ]]; then
    process_batch "${pending_accessions[@]}"
    echo "所有编号处理完成！" >&2
else
    echo "所有编号都已处理完成！" >&2
fi

# 清理进度文件（可选，如果希望保留断点续传能力则注释掉下面这行）
# rm -f "$progress_file"

echo "结果写在 $output" >&2
if [[ -f "$failed_log" ]] && [[ -s "$failed_log" ]]; then
    failed_count=$(wc -l < "$failed_log")
    echo "警告：有 $failed_count 个条目处理失败，详情见 $failed_log" >&2
fi
