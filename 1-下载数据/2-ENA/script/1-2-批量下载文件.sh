#!/usr/bin/env bash
set -uo pipefail
# 注意：去掉了 -e 选项，因为我们需要手动处理错误

unset http_proxy
unset https_proxy

#*######################################
#* 脚本功能：批量下载文件
#* 支持顺序下载和并行下载两种模式
#* 具备断点续传和重试机制
#*######################################

#*######################################
#* 用户配置：并行下载作业数量
#* 设置为1时使用顺序下载（原有逻辑）
#* 设置为>1时使用并行下载
#*######################################
PARALLEL_JOBS=5  # 用户可以修改这个数值

OUT_LIST="/mnt/g/luolintao/download.txt" #? 每行一个下载路径:vol1/run/ERR953/ERR9539070/10337.bam
SAVE_DIR="/mnt/g/luolintao/temp/" #? 下载保存目录

# 全局变量：当前正在下载的文件路径和进程管理
declare -A CURRENT_DOWNLOAD_FILES  # 关联数组：PID -> 文件路径
declare -A DOWNLOAD_PIDS           # 关联数组：用于跟踪所有下载进程
WGET_PID=""  # 保留原有的单个进程变量，用于向后兼容

# 初始化关联数组（确保在bash中正确声明）
CURRENT_DOWNLOAD_FILES=()
DOWNLOAD_PIDS=()

# 彩色打印函数
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

print_success() {
    echo -e "\033[32m[SUCCESS]\033[0m $1"
}

# 信号处理函数：清理并退出
cleanup_and_exit() {
    echo ""
    print_warn "检测到用户中断信号，正在清理..."
    
    # 终止所有并行下载进程
    if [[ ${#DOWNLOAD_PIDS[@]} -gt 0 ]]; then
        print_info "终止 ${#DOWNLOAD_PIDS[@]} 个并行下载进程..."
        for pid in "${!DOWNLOAD_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                print_info "终止进程: $pid"
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        
        # 等待进程终止
        sleep 2
        
        # 强制终止仍在运行的进程
        for pid in "${!DOWNLOAD_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                print_warn "强制终止进程: $pid"
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    # 兼容原有的单进程模式
    if [[ -n "$WGET_PID" ]]; then
        print_info "终止wget进程: $WGET_PID"
        kill -TERM "$WGET_PID" 2>/dev/null || true
        sleep 2
        if kill -0 "$WGET_PID" 2>/dev/null; then
            print_warn "强制终止wget进程"
            kill -KILL "$WGET_PID" 2>/dev/null || true
        fi
    fi
    
    # 删除所有未完成的下载文件
    for pid in "${!CURRENT_DOWNLOAD_FILES[@]}"; do
        local file_path="${CURRENT_DOWNLOAD_FILES[$pid]}"
        if [[ -n "$file_path" && -f "$file_path" ]]; then
            print_warn "删除未完成的下载文件: $(basename "$file_path")"
            rm -f "$file_path"
        fi
    done
    
    print_error "下载已被用户中断"
    exit 130  # 130 是标准的 SIGINT 退出码
}

# 注册信号处理函数
trap cleanup_and_exit SIGINT SIGTERM

# 单个文件下载函数：带重试和断点续传（用于顺序下载）
download_file() {
    local url="$1"
    local output_file="$2"
    local max_retries=3
    local retry_count=0
    
    # 检查文件是否已存在且大小不为0
    if [[ -f "$output_file" && -s "$output_file" ]]; then
        print_info "文件已存在且不为空，跳过下载: $(basename "$output_file")"
        return 0
    elif [[ -f "$output_file" && ! -s "$output_file" ]]; then
        print_warn "文件存在但大小为0，将重新下载: $(basename "$output_file")"
        rm -f "$output_file"
    fi
    
    print_info "开始下载: $(basename "$output_file")"
    
    while [[ $retry_count -lt $max_retries ]]; do
        # 启动wget并获取进程ID
        wget -c -t 3 -T 30 --progress=bar:force \
             --user-agent="Mozilla/5.0 (Linux; x86_64) wget" \
             -O "$output_file" "$url" &
        WGET_PID=$!
        
        # 等待wget完成
        if wait $WGET_PID; then
            WGET_PID=""  # 清空进程ID
            # 验证下载的文件大小
            if [[ -f "$output_file" && -s "$output_file" ]]; then
                print_success "下载完成: $(basename "$output_file")"
                return 0
            else
                print_error "下载的文件为空或不存在: $(basename "$output_file")"
                rm -f "$output_file"
            fi
        else
            WGET_PID=""  # 清空进程ID
            print_warn "wget进程异常退出"
        fi
        
        ((retry_count++))
        if [[ $retry_count -lt $max_retries ]]; then
            print_warn "下载失败，第 $retry_count 次重试..."
            sleep 5
        fi
    done
    
    print_error "下载失败，已达到最大重试次数: $(basename "$output_file")"
    return 1
}

# 并行下载单个文件的后台任务函数
download_file_background() {
    local url="$1"
    local output_file="$2"
    local task_id="$3"
    local max_retries=3
    local retry_count=0
    
    # 检查文件是否已存在且大小不为0
    if [[ -f "$output_file" && -s "$output_file" ]]; then
        print_info "[$task_id] 文件已存在且不为空，跳过下载: $(basename "$output_file")"
        return 0
    elif [[ -f "$output_file" && ! -s "$output_file" ]]; then
        print_warn "[$task_id] 文件存在但大小为0，将重新下载: $(basename "$output_file")"
        rm -f "$output_file"
    fi
    
    print_info "[$task_id] 开始下载: $(basename "$output_file")"
    
    while [[ $retry_count -lt $max_retries ]]; do
        # 启动wget下载
        if wget -c -t 3 -T 30 --progress=dot:mega \
               --user-agent="Mozilla/5.0 (Linux; x86_64) wget" \
               -O "$output_file" "$url" 2>/dev/null; then
            # 验证下载的文件大小
            if [[ -f "$output_file" && -s "$output_file" ]]; then
                print_success "[$task_id] 下载完成: $(basename "$output_file")"
                return 0
            else
                print_error "[$task_id] 下载的文件为空或不存在: $(basename "$output_file")"
                rm -f "$output_file"
            fi
        else
            print_warn "[$task_id] wget下载失败"
        fi
        
        ((retry_count++))
        if [[ $retry_count -lt $max_retries ]]; then
            print_warn "[$task_id] 下载失败，第 $retry_count 次重试..."
            sleep 5
        fi
    done
    
    print_error "[$task_id] 下载失败，已达到最大重试次数: $(basename "$output_file")"
    return 1
}

# 构造完整URL的辅助函数
construct_full_url() {
    local file_path="$1"
    if [[ "$file_path" =~ ^ftp:// || "$file_path" =~ ^http:// || "$file_path" =~ ^https:// ]]; then
        # 如果已经是完整URL，直接使用
        echo "$file_path"
    elif [[ "$file_path" =~ ^ftp\.sra\.ebi\.ac\.uk/ ]]; then
        # 如果是ENA的相对路径（包含域名但没有协议），添加ftp://
        echo "ftp://${file_path}"
    else
        # 如果是相对路径，添加完整的base URL
        echo "ftp://ftp.sra.ebi.ac.uk/${file_path}"
    fi
}

# 并行下载主函数
parallel_download() {
    local -a download_queue=()
    local -a failed_downloads=()
    local current_count=0
    local completed_count=0
    
    # 读取所有下载任务到队列
    while IFS= read -r file_path; do
        [[ -z "$file_path" || "$file_path" =~ ^[[:space:]]*# ]] && continue
        download_queue+=("$file_path")
    done < "$OUT_LIST"
    
    local total_files=${#download_queue[@]}
    print_info "总文件数: $total_files"
    print_info "并行作业数: $PARALLEL_JOBS"
    
    local queue_index=0
    
    while [[ $queue_index -lt $total_files || ${#DOWNLOAD_PIDS[@]} -gt 0 ]]; do
        # 启动新的下载任务，直到达到并行限制
        while [[ ${#DOWNLOAD_PIDS[@]} -lt $PARALLEL_JOBS && $queue_index -lt $total_files ]]; do
            local file_path="${download_queue[$queue_index]}"
            local filename=$(basename "$file_path")
            local output_file="$SAVE_DIR/$filename"
            local full_url=$(construct_full_url "$file_path")
            
            ((current_count++))
            local task_id="$current_count/$total_files"
            
            print_info "启动下载任务 [$task_id]: $filename"
            
            # 启动后台下载任务
            download_file_background "$full_url" "$output_file" "$task_id" &
            local pid=$!
            
            # 记录进程信息
            DOWNLOAD_PIDS[$pid]="$file_path"
            CURRENT_DOWNLOAD_FILES[$pid]="$output_file"
            
            ((queue_index++))
        done
        
        # 检查已完成的下载任务
        for pid in "${!DOWNLOAD_PIDS[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                # 进程已结束，检查退出状态
                wait "$pid"
                local exit_code=$?
                local file_path="${DOWNLOAD_PIDS[$pid]}"
                
                if [[ $exit_code -eq 0 ]]; then
                    ((completed_count++))
                else
                    failed_downloads+=("$file_path")
                fi
                
                # 清理进程记录
                unset DOWNLOAD_PIDS[$pid]
                unset CURRENT_DOWNLOAD_FILES[$pid]
            fi
        done
        
        # 短暂休眠，避免过度占用CPU
        sleep 1
    done
    
    # 输出下载结果统计
    echo ""
    print_info "并行下载任务完成！"
    print_info "总文件数: $total_files"
    print_info "成功下载: $((total_files - ${#failed_downloads[@]}))"
    
    if [[ ${#failed_downloads[@]} -gt 0 ]]; then
        print_error "失败下载: ${#failed_downloads[@]}"
        print_error "失败的文件列表:"
        for failed_file in "${failed_downloads[@]}"; do
            echo "  - $failed_file"
        done
        return 1
    else
        print_success "所有文件下载成功！"
        return 0
    fi
}

# 顺序下载主函数（原有逻辑）
sequential_download() {
    local current_count=0
    local failed_downloads=()
    local total_files=$(wc -l < "$OUT_LIST")
    
    print_info "总文件数: $total_files"
    print_info "使用顺序下载模式"
    
    while IFS= read -r file_path; do
        # 跳过空行和注释行
        [[ -z "$file_path" || "$file_path" =~ ^[[:space:]]*# ]] && continue
        
        ((current_count++))
        local filename=$(basename "$file_path")
        local output_file="$SAVE_DIR/$filename"
        local full_url=$(construct_full_url "$file_path")
        
        print_info "[$current_count/$total_files] 处理文件: $filename"
        
        if ! download_file "$full_url" "$output_file"; then
            failed_downloads+=("$file_path")
        fi
        
        echo "----------------------------------------"
    done < "$OUT_LIST"
    
    # 输出下载结果统计
    echo ""
    print_info "顺序下载任务完成！"
    print_info "总文件数: $total_files"
    print_info "成功下载: $((total_files - ${#failed_downloads[@]}))"
    
    if [[ ${#failed_downloads[@]} -gt 0 ]]; then
        print_error "失败下载: ${#failed_downloads[@]}"
        print_error "失败的文件列表:"
        for failed_file in "${failed_downloads[@]}"; do
            echo "  - $failed_file"
        done
        return 1
    else
        print_success "所有文件下载成功！"
        return 0
    fi
}

# 检查下载列表文件是否存在
if [[ ! -f "$OUT_LIST" ]]; then
    print_error "下载列表文件不存在: $OUT_LIST"
    print_error "请先运行生成下载列表的脚本"
    exit 1
fi

# 检查下载列表是否为空
if [[ ! -s "$OUT_LIST" ]]; then
    print_error "下载列表文件为空: $OUT_LIST"
    exit 1
fi

# 主下载逻辑
print_info "开始批量下载文件..."
print_info "下载列表: $OUT_LIST"
print_info "保存目录: $SAVE_DIR"

# 确保保存目录存在
mkdir -p "$SAVE_DIR"

# 显示下载列表预览
total_files=$(wc -l < "$OUT_LIST")
print_info "下载列表预览（前3行，共 $total_files 个文件）:"
head -3 "$OUT_LIST" | while IFS= read -r line; do
    echo "  - $(basename "$line")"
done
if [[ $total_files -gt 3 ]]; then
    echo "  ... 还有 $((total_files - 3)) 个文件"
fi

# 根据并行作业数选择下载模式
exit_code=0
if [[ $PARALLEL_JOBS -eq 1 ]]; then
    sequential_download
    exit_code=$?
else
    parallel_download
    exit_code=$?
fi

exit $exit_code