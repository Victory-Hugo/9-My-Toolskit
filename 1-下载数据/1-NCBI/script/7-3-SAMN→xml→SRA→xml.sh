#!/bin/bash

# 脚本功能：读取SAMPLE编号文件，获取biosample的XML数据（支持并行处理）
# 作者：Lintao Luo
# 日期：2025年12月16日
# 修改：仅保留SAMN→XML功能

unset http_proxy
unset https_proxy

# 从调用脚本接收参数
INPUT_FILE="${1:-/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/1-NCBI/conf/biosample1.txt}"
BIOSAMPLE_DIR="${2:-/mnt/c/Users/Administrator/Desktop/biosample_xml}"
LOG_FILE="${3:-/mnt/c/Users/Administrator/Desktop/download_log.txt}"
PARALLEL_JOBS="${4:-6}"  # 默认并行任务数

# NCBI API配置
NCBI_API_KEY="29b326d54e7a21fc6c8b9afe7d71f441d809" #!请自己在NCBI申请API密钥
export NCBI_API_KEY

# API使用说明：
# 有了API密钥后，可以享受以下优势：
# 1. 更高的请求频率限制（10次/秒 vs 3次/秒）
# 2. 更稳定的服务质量
# 3. 优先处理请求
# 4. 支持更高的并行数

# 创建输出目录
mkdir -p "$BIOSAMPLE_DIR"

# 初始化日志文件
init_log_file() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "# Biosample Download Log - Created on $(date)" > "$LOG_FILE"
        echo "# Format: TIMESTAMP | SAMPLE_ID | STATUS | BIOSAMPLE_FILE | NOTES" >> "$LOG_FILE"
        echo "# STATUS: SUCCESS/FAILED/SKIPPED" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
}

# 记录日志的函数
log_result() {
    local sample_id="$1"
    local status="$2"
    local biosample_file="$3"
    local notes="$4"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp | $sample_id | $status | $biosample_file | $notes" >> "$LOG_FILE"
}

# 检查样本是否已经成功处理
is_sample_completed() {
    local sample_id="$1"
    if [ -f "$LOG_FILE" ]; then
        # 检查日志中是否有该样本的成功记录
        grep -q "| $sample_id | SUCCESS |" "$LOG_FILE"
        return $?
    fi
    return 1  # 日志文件不存在，认为未完成
}

# 获取失败的样本列表
get_failed_samples() {
    if [ -f "$LOG_FILE" ]; then
        grep "| FAILED |" "$LOG_FILE" | cut -d'|' -f2 | tr -d ' ' | sort -u
    fi
}

# 处理单个样本的函数
process_sample() {
    local sample_id="$1"
    local current="$2"
    local total="$3"
    
    # 去除可能的空白字符
    sample_id=$(echo "$sample_id" | tr -d '[:space:]')
    
    # 跳过空的sample_id
    if [ -z "$sample_id" ]; then
        echo "跳过空的sample_id"
        return
    fi
    
    echo "[$current/$total] 处理SAMPLE: $sample_id (PID: $$)"
    
    # 检查是否已经成功处理过
    if is_sample_completed "$sample_id"; then
        echo "  [$$] ✓ 样本 $sample_id 已在之前成功处理，跳过"
        log_result "$sample_id" "SKIPPED" "ALREADY_EXISTS" "Previously completed"
        return
    fi
    
    # 获取biosample的XML
    biosample_xml="$BIOSAMPLE_DIR/${sample_id}.xml"
    echo "  [$$] 正在获取biosample XML..."
    
    if esearch -db biosample -query "$sample_id" | efetch -format xml > "$biosample_xml" 2>/dev/null; then
        if [ -s "$biosample_xml" ]; then
            echo "  [$$] ✓ Biosample XML已保存: $biosample_xml"
            log_result "$sample_id" "SUCCESS" "$biosample_xml" "Biosample XML downloaded successfully"
            echo "  [$$] ✓ 完成处理: $sample_id"
        else
            echo "  [$$] ✗ Biosample XML为空，可能未找到该SAMPLE"
            rm -f "$biosample_xml"
            log_result "$sample_id" "FAILED" "NOT_FOUND" "Biosample not found"
            echo "  [$$] ✗ 失败: $sample_id"
        fi
    else
        echo "  [$$] ✗ 获取biosample XML失败"
        log_result "$sample_id" "FAILED" "API_ERROR" "Biosample API error"
        echo "  [$$] ✗ 失败: $sample_id"
    fi
}
# 导出函数以便子进程使用
export -f process_sample is_sample_completed log_result
export BIOSAMPLE_DIR LOG_FILE NCBI_API_KEY

# 检查输入文件是否存在
if [ ! -f "$INPUT_FILE" ]; then
    echo "错误：输入文件 $INPUT_FILE 不存在！"
    exit 1
fi

# 检查并行任务数是否合理
if ! [[ "$PARALLEL_JOBS" =~ ^[0-9]+$ ]] || [ "$PARALLEL_JOBS" -lt 1 ] || [ "$PARALLEL_JOBS" -gt 20 ]; then
    echo "错误：并行任务数必须是1-20之间的整数！"
    echo "使用方法: $0 [并行任务数]"
    echo "例如: $0 5  # 使用5个并行任务"
    exit 1
fi

# 检查是否安装了必要的工具
if ! command -v esearch &> /dev/null; then
    echo "错误：edirect工具未安装！请先安装NCBI E-utilities。"
    echo "安装命令："
    echo "conda install -c bioconda entrez-direct"
    echo "或者"
    echo "sh -c \"\$(curl -fsSL ftp://ftp.ncbi.nlm.nih.gov/entrez/entrezdirect/install-edirect.sh)\""
    exit 1
fi

# 初始化日志文件
init_log_file

echo "开始处理SAMPLE编号..."
echo "输入文件：$INPUT_FILE"
echo "Biosample XML输出目录：$BIOSAMPLE_DIR"
echo "日志文件：$LOG_FILE"
echo "NCBI API密钥：已配置 (${NCBI_API_KEY:0:8}...)"
echo "并行任务数：$PARALLEL_JOBS"
echo "================================"

# 读取所有非空行到数组
mapfile -t samples < <(grep -v '^[[:space:]]*$' "$INPUT_FILE")
total_samples=${#samples[@]}

echo "文件中共有 $total_samples 个有效样本"

# 检查已完成的样本
completed_count=0
if [ -f "$LOG_FILE" ]; then
    completed_count=$(grep -c "| SUCCESS |" "$LOG_FILE" 2>/dev/null || echo "0")
    completed_count=$(echo "$completed_count" | tr -d '\n\r ')  # 清理换行符和空格
fi

echo "已完成样本数：$completed_count"
remaining_count=$((total_samples - completed_count))
echo "需要处理样本数：$remaining_count"
echo "使用 $PARALLEL_JOBS 个并行任务进行处理..."
echo "================================"

# 创建临时文件来存储任务
temp_task_file=$(mktemp)
trap "rm -f $temp_task_file" EXIT

# 将任务写入临时文件
for i in "${!samples[@]}"; do
    current=$((i + 1))
    echo "process_sample \"${samples[$i]}\" $current $total_samples" >> "$temp_task_file"
done

# 使用xargs并行执行任务
echo "开始并行处理（最大并行数：$PARALLEL_JOBS）..."
echo "进程输出中的 [PID] 表示处理该样本的进程ID"
echo "================================"

if command -v xargs &> /dev/null; then
    # 使用xargs进行并行处理
    cat "$temp_task_file" | xargs -n 4 -P "$PARALLEL_JOBS" -I {} bash -c '{}'
else
    echo "警告：xargs不可用，使用串行处理..."
    # 备用方案：串行处理
    while IFS= read -r task; do
        eval "$task"
        sleep 0.5  # 添加延迟避免API过载
    done < "$temp_task_file"
fi

echo "================================"
echo "所有SAMPLE处理完成！"
echo "Biosample XML文件保存在: $BIOSAMPLE_DIR"

# 显示统计信息
biosample_count=$(find "$BIOSAMPLE_DIR" -name "*.xml" 2>/dev/null | wc -l)

echo ""
echo "统计信息："
echo "- 成功获取的Biosample XML: $biosample_count 个"

# 显示日志统计
if [ -f "$LOG_FILE" ]; then
    echo ""
    echo "详细统计（基于日志文件）："
    success_count=$(grep -c "| SUCCESS |" "$LOG_FILE" 2>/dev/null || echo "0")
    failed_count=$(grep -c "| FAILED |" "$LOG_FILE" 2>/dev/null || echo "0")
    skipped_count=$(grep -c "| SKIPPED |" "$LOG_FILE" 2>/dev/null || echo "0")
    
    echo "- 成功: $success_count 个"
    echo "- 失败: $failed_count 个"
    echo "- 已跳过: $skipped_count 个"
    
    # 显示失败的样本
    failed_samples=$(get_failed_samples)
    if [ -n "$failed_samples" ]; then
        echo ""
        echo "需要重新处理的失败样本："
        echo "$failed_samples"
        
        # 创建失败样本的重试文件
        retry_file="/mnt/c/Users/Administrator/Desktop/retry_samples.txt"
        echo "$failed_samples" > "$retry_file"
        echo ""
        echo "失败样本已保存到: $retry_file"
        echo "可以使用以下命令重新处理失败的样本："
        echo "  sed -i 's|INPUT_FILE=.*|INPUT_FILE=\"$retry_file\"|' $0"
        echo "  $0"
    fi
fi

echo ""
echo "获取的文件列表："
echo "Biosample XML文件:"
find "$BIOSAMPLE_DIR" -name "*.xml" 2>/dev/null | sort

echo ""
echo "断点续跑功能："
echo "- 脚本会记录每个样本的处理状态到日志文件"
echo "- 重新运行脚本时会自动跳过已成功处理的样本"
echo "- 失败的样本会记录详细错误信息，方便后续重试"
echo "- 日志文件位置: $LOG_FILE"
echo ""
echo "日志文件格式说明："
echo "- SUCCESS: Biosample获取成功"
echo "- FAILED: Biosample获取失败"
echo "- SKIPPED: 已处理过，本次跳过"
echo ""
echo "脚本支持并行处理，可通过调用脚本时传入参数调整并行数："
echo "  调用格式: script INPUT_FILE BIOSAMPLE_DIR LOG_FILE PARALLEL_JOBS"
echo "  例如: $0 input.txt output_dir log.txt 8"
echo ""
echo "API密钥优势建议："
echo "- 有API密钥时可使用较高并行数（5-15）"
echo "- API密钥提供10次/秒的请求限制（vs 普送3次/秒）"
echo "- 如果遇到问题，可降低并行数或稍后重试"
