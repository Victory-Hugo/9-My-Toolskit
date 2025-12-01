#!/bin/bash

# 脚本功能：读取SAMPLE编号文件，获取biosample和SRA的XML数据（支持并行处理）
# 作者：Lintao Luo
# 日期：2025年8月19日

unset http_proxy
unset https_proxy

# 默认配置
INPUT_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/conf/biosample1.txt"
BIOSAMPLE_DIR="/mnt/c/Users/Administrator/Desktop/biosample_xml"
SRA_DIR="/mnt/c/Users/Administrator/Desktop/SRA_xml"
LOG_FILE="/mnt/c/Users/Administrator/Desktop/download_log.txt"
DEFAULT_PARALLEL_JOBS=6  # 默认并行任务数（使用API密钥可以提高）

# NCBI API配置
NCBI_API_KEY="29b326d54e7a21fc6c8b9afe7d71f441d809" #!请自己在NCBI申请API密钥
export NCBI_API_KEY

# API使用说明：
# 有了API密钥后，可以享受以下优势：
# 1. 更高的请求频率限制（10次/秒 vs 3次/秒）
# 2. 更稳定的服务质量
# 3. 优先处理请求
# 4. 支持更高的并行数

# 并行任务数（可通过命令行参数调整）
PARALLEL_JOBS=${1:-$DEFAULT_PARALLEL_JOBS}

# 创建输出目录
mkdir -p "$BIOSAMPLE_DIR"
mkdir -p "$SRA_DIR"

# 初始化日志文件
init_log_file() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "# Download Log - Created on $(date)" > "$LOG_FILE"
        echo "# Format: TIMESTAMP | SAMPLE_ID | STATUS | BIOSAMPLE_FILE | SRA_FILES | NOTES" >> "$LOG_FILE"
        echo "# STATUS: SUCCESS/BIOSAMPLE_FAILED/SRA_FAILED/SKIPPED" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
}

# 记录日志的函数
log_result() {
    local sample_id="$1"
    local status="$2"
    local biosample_file="$3"
    local sra_files="$4"
    local notes="$5"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp | $sample_id | $status | $biosample_file | $sra_files | $notes" >> "$LOG_FILE"
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
        grep -E "| (BIOSAMPLE_FAILED|SRA_FAILED) |" "$LOG_FILE" | cut -d'|' -f2 | tr -d ' ' | sort -u
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
        log_result "$sample_id" "SKIPPED" "ALREADY_EXISTS" "ALREADY_EXISTS" "Previously completed"
        return
    fi
    
    # 初始化变量
    local biosample_status="FAILED"
    local sra_status="FAILED"
    local biosample_file=""
    local sra_files=""
    local notes=""
    
    # 1. 获取biosample的XML
    biosample_xml="$BIOSAMPLE_DIR/${sample_id}.xml"
    echo "  [$$] 正在获取biosample XML..."
    
    if esearch -db biosample -query "$sample_id" | efetch -format xml > "$biosample_xml" 2>/dev/null; then
        if [ -s "$biosample_xml" ]; then
            echo "  [$$] ✓ Biosample XML已保存: $biosample_xml"
            biosample_status="SUCCESS"
            biosample_file="$biosample_xml"
        else
            echo "  [$$] ✗ Biosample XML为空，可能未找到该SAMPLE"
            rm -f "$biosample_xml"
            notes="Biosample not found"
            log_result "$sample_id" "BIOSAMPLE_FAILED" "NOT_FOUND" "" "$notes"
            echo "  [$$] 跳过: $sample_id"
            return
        fi
    else
        echo "  [$$] ✗ 获取biosample XML失败"
        notes="Biosample API error"
        log_result "$sample_id" "BIOSAMPLE_FAILED" "API_ERROR" "" "$notes"
        echo "  [$$] 跳过: $sample_id"
        return
    fi
    
    # 2. 尝试获取关联的SRA数据
    echo "  [$$] 正在搜索关联的SRA数据..."
    
    # 方法1：从biosample XML中直接提取SRA ID
    echo "    [$$] 尝试方法1: 从biosample XML提取SRA ID..."
    sra_ids=$(grep '<Id db="SRA">' "$biosample_xml" | sed 's/.*<Id db="SRA">\([^<]*\)<\/Id>.*/\1/' | sort -u 2>/dev/null)
    
    # 方法2：通过elink链接
    if [ -z "$sra_ids" ]; then
        echo "    [$$] 尝试方法2: elink..."
        # 提取所有SRA相关的ID（支持SRR/ERR/DRR/SRS/DRS等格式）
        sra_ids=$(esearch -db biosample -query "$sample_id" | elink -target sra | esummary | grep -E "<Item Name=\"Run\".*>|<Item Name=\"Experiment\".*>" | sed 's/.*>\([^<]*\)<.*/\1/' | grep -E "[SED]R[RS][0-9]+|DRS[0-9]+" | sort -u 2>/dev/null)
        
        # 如果仍未找到，尝试更通用的提取方式
        if [ -z "$sra_ids" ]; then
            sra_ids=$(esearch -db biosample -query "$sample_id" | elink -target sra | esummary | grep -oE "[SED]R[RS][0-9]+|DRS[0-9]+" | sort -u 2>/dev/null)
        fi
    fi
    
    # 方法3：如果没找到，尝试直接搜索
    if [ -z "$sra_ids" ]; then
        echo "    [$$] 尝试方法3: 直接搜索..."
        sra_ids=$(esearch -db sra -query "$sample_id" | esummary | grep -oE "[SED]R[RS][0-9]+|DRS[0-9]+" | sort -u 2>/dev/null)
    fi
    
    # 方法4：通过bioproject搜索
    if [ -z "$sra_ids" ]; then
        # 从XML中提取bioproject ID（支持多种格式）
        bioproject_id=$(grep -E '<Link.*target="bioproject".*>|<Id db="BioProject">' "$biosample_xml" | head -1)
        if [ -n "$bioproject_id" ]; then
            # 提取bioproject ID，支持PRJNA、PRJDB等格式
            if echo "$bioproject_id" | grep -q 'target="bioproject"'; then
                # 从Link标签中提取：<Link type="entrez" target="bioproject" label="PRJDB3841">298563</Link>
                project_id=$(echo "$bioproject_id" | sed 's/.*label="\([^"]*\)".*/\1/')
            else
                # 从Id标签中提取：<Id db="BioProject">PRJNA123456</Id>
                project_id=$(echo "$bioproject_id" | sed 's/.*<Id db="BioProject">\([^<]*\)<\/Id>.*/\1/')
            fi
            
            if [ -n "$project_id" ]; then
                echo "    [$$] 尝试方法4: 通过bioproject $project_id 搜索..."
                sra_ids=$(esearch -db sra -query "$project_id" | esummary | grep -oE "[SED]R[RS][0-9]+|DRS[0-9]+" | sort -u 2>/dev/null)
            fi
        fi
    fi
    
    if [ -n "$sra_ids" ]; then
        echo "  [$$] ✓ 找到SRA数据:"
        local successful_sra=""
        local failed_sra=""
        
        for sra_id in $sra_ids; do
            if [ -n "$sra_id" ]; then
                echo "    [$$] 处理 $sra_id..."
                sra_xml="$SRA_DIR/${sra_id}.xml"
                if esearch -db sra -query "$sra_id" | efetch -format xml > "$sra_xml" 2>/dev/null; then
                    if [ -s "$sra_xml" ]; then
                        echo "    [$$] ✓ SRA XML已保存: $sra_xml"
                        successful_sra="$successful_sra $sra_id"
                    else
                        rm -f "$sra_xml"
                        echo "    [$$] ✗ SRA XML为空: $sra_id"
                        failed_sra="$failed_sra $sra_id"
                    fi
                else
                    echo "    [$$] ✗ 获取SRA XML失败: $sra_id"
                    failed_sra="$failed_sra $sra_id"
                fi
            fi
        done
        
        # 整理SRA结果
        successful_sra=$(echo "$successful_sra" | tr ' ' ',' | sed 's/^,//' | sed 's/,$//')
        failed_sra=$(echo "$failed_sra" | tr ' ' ',' | sed 's/^,//' | sed 's/,$//')
        
        if [ -n "$successful_sra" ]; then
            sra_status="SUCCESS"
            sra_files="$successful_sra"
            if [ -n "$failed_sra" ]; then
                notes="SRA partial success. Failed: $failed_sra"
            else
                notes="All SRA files downloaded successfully"
            fi
        else
            sra_status="FAILED"
            notes="All SRA downloads failed: $failed_sra"
        fi
    else
        echo "  [$$] ! 未找到关联的SRA数据"
        sra_status="NOT_FOUND"
        notes="No associated SRA data found"
    fi
    
    # 记录最终结果
    if [ "$biosample_status" = "SUCCESS" ] && [ "$sra_status" = "SUCCESS" ]; then
        log_result "$sample_id" "SUCCESS" "$biosample_file" "$sra_files" "$notes"
        echo "  [$$] ✓ 完成处理: $sample_id (SUCCESS)"
    elif [ "$biosample_status" = "SUCCESS" ] && [ "$sra_status" = "NOT_FOUND" ]; then
        log_result "$sample_id" "SUCCESS" "$biosample_file" "NO_SRA" "$notes"
        echo "  [$$] ✓ 完成处理: $sample_id (BIOSAMPLE_ONLY)"
    elif [ "$sra_status" = "FAILED" ]; then
        log_result "$sample_id" "SRA_FAILED" "$biosample_file" "FAILED" "$notes"
        echo "  [$$] ✗ 完成处理: $sample_id (SRA_FAILED)"
    fi
}

# 导出函数以便子进程使用
export -f process_sample is_sample_completed log_result
export BIOSAMPLE_DIR SRA_DIR LOG_FILE NCBI_API_KEY

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
echo "SRA XML输出目录：$SRA_DIR"
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
echo "SRA XML文件保存在: $SRA_DIR"

# 显示统计信息
biosample_count=$(find "$BIOSAMPLE_DIR" -name "*.xml" 2>/dev/null | wc -l)
sra_count=$(find "$SRA_DIR" -name "*.xml" 2>/dev/null | wc -l)

echo ""
echo "统计信息："
echo "- 成功获取的Biosample XML: $biosample_count 个"
echo "- 成功获取的SRA XML: $sra_count 个"

# 显示日志统计
if [ -f "$LOG_FILE" ]; then
    echo ""
    echo "详细统计（基于日志文件）："
    success_count=$(grep -c "| SUCCESS |" "$LOG_FILE" 2>/dev/null || echo "0")
    biosample_failed_count=$(grep -c "| BIOSAMPLE_FAILED |" "$LOG_FILE" 2>/dev/null || echo "0")
    sra_failed_count=$(grep -c "| SRA_FAILED |" "$LOG_FILE" 2>/dev/null || echo "0")
    skipped_count=$(grep -c "| SKIPPED |" "$LOG_FILE" 2>/dev/null || echo "0")
    
    echo "- 完全成功: $success_count 个"
    echo "- Biosample失败: $biosample_failed_count 个"
    echo "- SRA失败: $sra_failed_count 个"
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
echo "SRA XML文件:"
find "$SRA_DIR" -name "*.xml" 2>/dev/null | sort

echo ""
echo "断点续跑功能："
echo "- 脚本会记录每个样本的处理状态到日志文件"
echo "- 重新运行脚本时会自动跳过已成功处理的样本"
echo "- 失败的样本会记录详细错误信息，方便后续重试"
echo "- 日志文件位置: $LOG_FILE"
echo ""
echo "日志文件格式说明："
echo "- SUCCESS: 样本完全处理成功"
echo "- BIOSAMPLE_FAILED: Biosample获取失败"
echo "- SRA_FAILED: SRA数据获取失败"
echo "- SKIPPED: 已处理过，本次跳过"
echo "脚本支持并行处理，可通过命令行参数调整并行数："
echo "  $0           # 使用默认并行数 ($DEFAULT_PARALLEL_JOBS) - 已优化API密钥"
echo "  $0 8         # 使用8个并行任务 - API密钥支持更高并发"
echo "  $0 1         # 单线程处理（最安全，但最慢）"
echo "  $0 15        # 使用15个并行任务（高速模式，API密钥支持）"
echo ""
echo "API密钥优势建议："
echo "- 有API密钥时可使用较高并行数（5-15）"
echo "- API密钥提供10次/秒的请求限制（vs 普通3次/秒）"
echo "- 网络很好时可尝试最高15个并行任务"
echo "- 网络一般时建议5-8个并行任务"
echo "- 如果遇到问题，可降低并行数或稍后重试"
