#!/usr/bin/env bash
# SRA 批量下载脚本（改进版）
# 依赖：GNU parallel, prefetch
# 
# 使用方法：
#   ./3-NCBI-SRA-download.sh         # 断点续跑模式（默认，仅下载失败和未完成的）
#   ./3-NCBI-SRA-download.sh -n      # 正常下载模式（下载所有样本）
#   ./3-NCBI-SRA-download.sh -s      # 安全模式（每次验证文件完整性）
#   ./3-NCBI-SRA-download.sh -n -s   # 正常下载 + 安全模式


####################################
# 基本参数                          #
####################################
#TODO : 修改以下参数以适应你的环境
unset http_proxy
unset https_proxy
# PROJ="鲍曼NC2025_1"
SRA_LIST="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/1-NCBI/conf/下载SRA.txt" # 格式：每行一个 SRA/ERR/DRR 号

# prefetch 可执行文件路径
PREFETCH="/mnt/e/Scientifc_software/sratoolkit.3.1.1-ubuntu64/bin/prefetch"

OUTDIR="/mnt/d/6-HPgnomAD-Origin-data/5-NCBI/2-Sequence/"

mkdir -p "$OUTDIR" || { echo "无法创建输出目录: $OUTDIR"; exit 1; }

# 下载配置
JOBS=5               # 并行任务数（如果为 1，则切换为串行模式）
MAX_RETRY=3          # 每个 accession 最多重试次数
FAILED_LIST="$OUTDIR/failed.list"   # 永久失败列表
JOBLOG="$OUTDIR/joblog.txt"         # parallel 运行日志

# 日志文件配置
SUCCESS_LOG="$OUTDIR/success.log"     # 成功下载日志
FAILED_LOG="$OUTDIR/failed.log"       # 失败下载日志
SKIPPED_LOG="$OUTDIR/skipped.log"     # 跳过下载日志
DOWNLOAD_LOG="$OUTDIR/download.log"   # 总体下载日志
STATUS_FILE="$OUTDIR/download_status.txt"  # 下载状态文件

# 断点续跑模式
RESUME_MODE=true     # 默认启用断点续跑模式（可通过 -n 参数禁用）

# 性能优化选项
FAST_MODE=true       # 快速模式：优先使用状态文件，减少文件系统扫描（默认启用）
####################################

# 检查依赖
if [ "$JOBS" -gt 1 ]; then
    command -v parallel >/dev/null 2>&1 || { echo "请先安装 GNU parallel"; exit 1; }
fi
[ -x "$PREFETCH" ] || { echo "prefetch 路径无效: $PREFETCH"; exit 1; }
[ -f "$SRA_LIST" ] || { echo "SRA 列表文件不存在: $SRA_LIST"; exit 1; }

# 解析命令行参数
while getopts "ns" opt; do
    case $opt in
        n)
            RESUME_MODE=false
            echo "禁用断点续跑模式，下载所有样本"
            ;;
        s)
            FAST_MODE=false
            echo "启用安全模式（禁用快速模式，每次都验证文件完整性）"
            ;;
        \?)
            echo "用法: $0 [-n] [-s]"
            echo "  -n: 禁用断点续跑模式，下载所有样本（默认启用断点续跑）"
            echo "  -s: 启用安全模式，禁用快速模式，每次都验证文件完整性"
            exit 1
            ;;
    esac
done

# 日志记录函数
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$DOWNLOAD_LOG"
}

log_success() {
    local acc="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] SUCCESS: $acc - $message" >> "$SUCCESS_LOG"
    echo "[$timestamp] SUCCESS: $acc - $message" >> "$DOWNLOAD_LOG"
    echo "$acc SUCCESS" >> "$STATUS_FILE"
}

log_failure() {
    local acc="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] FAILED: $acc - $message" >> "$FAILED_LOG"
    echo "[$timestamp] FAILED: $acc - $message" >> "$DOWNLOAD_LOG"
    echo "$acc FAILED" >> "$STATUS_FILE"
}

log_skip() {
    local acc="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] SKIPPED: $acc - $message" >> "$SKIPPED_LOG"
    echo "[$timestamp] SKIPPED: $acc - $message" >> "$DOWNLOAD_LOG"
    echo "$acc SKIPPED" >> "$STATUS_FILE"
}

# 检查文件是否已完整下载
check_file_complete() {
    local acc="$1"
    local sra_dir="$OUTDIR/$acc"
    
    if [ -d "$sra_dir" ]; then
        # 检查是否有.sra文件且大小大于0
        if find "$sra_dir" -name "*.sra" -type f -size +0 | grep -q .; then
            return 0  # 文件完整
        fi
    fi
    return 1  # 文件不完整或不存在
}

# 获取需要下载的样本列表
get_download_list() {
    local temp_list="/tmp/sra_download_list.$$"
    
    if [ "$RESUME_MODE" = true ] && [ -f "$STATUS_FILE" ]; then
        log_message "断点续跑模式: 分析之前的下载状态..."
        
        # 创建临时文件存储需要下载的样本
        > "$temp_list"
        
        while read -r acc; do
            [ -z "$acc" ] && continue
            
            # 仅检查状态文件中的记录，不扫盘验证
            if grep -q "^$acc SUCCESS" "$STATUS_FILE" 2>/dev/null; then
                continue  # 已成功，跳过
            elif grep -q "^$acc SKIPPED" "$STATUS_FILE" 2>/dev/null; then
                continue  # 之前跳过，继续跳过
            fi
            
            # 需要下载的样本（失败的、未记录的）
            echo "$acc" >> "$temp_list"
        done < "$SRA_LIST"
        
        echo "$temp_list"
    else
        echo "$SRA_LIST"
    fi
}

# 下载函数
fetch_one() {
    acc="$1"

    # 在正常下载模式下，快速检查状态文件避免重复下载
    if [ "$RESUME_MODE" = false ] && [ "$FAST_MODE" = true ] && [ -f "$STATUS_FILE" ]; then
        if grep -q "^$acc SUCCESS" "$STATUS_FILE" 2>/dev/null; then
            log_skip "$acc" "状态文件显示已成功下载"
            echo "$acc 状态文件显示已下载，跳过"
            return 0
        elif grep -q "^$acc SKIPPED" "$STATUS_FILE" 2>/dev/null; then
            log_skip "$acc" "状态文件显示之前已跳过"
            echo "$acc 状态文件显示之前已跳过，继续跳过"
            return 0
        fi
    fi

    # 仅在必要时检查文件完整性（当状态文件不存在或无记录时，或安全模式下）
    if [ "$FAST_MODE" = false ] || [ ! -f "$STATUS_FILE" ] || ! grep -q "^$acc " "$STATUS_FILE" 2>/dev/null; then
        if check_file_complete "$acc"; then
            log_skip "$acc" "文件已存在且完整"
            echo "$acc 已存在且完整，跳过"
            return 0
        fi
    fi
    
    # 清理可能存在的不完整文件
    if [ -d "$OUTDIR/$acc" ]; then
        log_message "$acc 发现不完整的下载目录，清理后重新下载"
        rm -rf "$OUTDIR/$acc"
    fi

    log_message "$acc 开始下载..."
    echo "开始下载 $acc ..."
    
    local success=false
    for ((i=1; i<=MAX_RETRY; i++)); do
        log_message "$acc 第 $i/$MAX_RETRY 次尝试下载"
        
        if "$PREFETCH" --output-directory "$OUTDIR" "$acc" --progress; then
            # 验证下载是否成功
            if check_file_complete "$acc"; then
                log_success "$acc" "下载成功 (尝试 $i/$MAX_RETRY 次)"
                echo "$acc 下载成功"
                success=true
                break
            else
                log_message "$acc 第 $i 次下载命令成功但文件验证失败"
                # 清理不完整的文件
                [ -d "$OUTDIR/$acc" ] && rm -rf "$OUTDIR/$acc"
            fi
        else
            log_message "$acc 第 $i/$MAX_RETRY 次下载失败"
            echo "$acc 第 $i/$MAX_RETRY 次下载失败，重试中…" >&2
        fi
        
        sleep 1
    done

    # 最终检查
    if [ "$success" = false ]; then
        log_failure "$acc" "经过 $MAX_RETRY 次尝试仍失败"
        echo "$acc 经过 $MAX_RETRY 次尝试仍失败，记录到失败日志" >&2
        echo "$acc" >> "$FAILED_LIST"
    fi
    
    # 始终返回 0，以免 parallel 因失败而早停
    return 0
}

export -f fetch_one check_file_complete log_success log_failure log_skip log_message
export PREFETCH OUTDIR MAX_RETRY FAILED_LIST SUCCESS_LOG FAILED_LOG SKIPPED_LOG DOWNLOAD_LOG STATUS_FILE RESUME_MODE FAST_MODE

####################################
# 运行逻辑                          #
####################################
mkdir -p "$OUTDIR"

# 初始化日志文件
if [ "$RESUME_MODE" = false ]; then
    # 正常下载模式，清空所有日志
    : > "$SUCCESS_LOG"
    : > "$FAILED_LOG"
    : > "$SKIPPED_LOG"
    : > "$DOWNLOAD_LOG"
    : > "$STATUS_FILE"
    : > "$FAILED_LIST"
    log_message "开始正常下载任务（下载所有样本）"
else
    # 断点续跑模式，仅清空本次运行的临时日志
    : > "$FAILED_LIST"
    log_message "断点续跑模式：仅下载失败和未完成的样本"
fi

# 获取需要下载的样本列表
log_message "生成下载样本列表..."
ACTUAL_LIST=$(get_download_list)
log_message "样本列表文件: $ACTUAL_LIST"

# 检查列表文件是否有效
if [ ! -f "$ACTUAL_LIST" ]; then
    echo "错误：无法生成或访问样本列表文件: $ACTUAL_LIST"
    echo "原始SRA列表文件: $SRA_LIST"
    echo "SRA列表文件是否存在: $([ -f "$SRA_LIST" ] && echo "是" || echo "否")"
    exit 1
fi

# 统计信息
TOTAL_COUNT=$(wc -l < "$SRA_LIST")
if [ "$RESUME_MODE" = true ]; then
    DOWNLOAD_COUNT=$([ -f "$ACTUAL_LIST" ] && wc -l < "$ACTUAL_LIST" || echo "0")
    log_message "总样本数: $TOTAL_COUNT, 需要下载数: $DOWNLOAD_COUNT"
    
    if [ "$DOWNLOAD_COUNT" -eq 0 ]; then
        log_message "所有样本均已完成下载，无需继续"
        echo "所有样本均已完成下载，退出。"
        # 清理临时文件
        [ -f "$ACTUAL_LIST" ] && [ "$ACTUAL_LIST" != "$SRA_LIST" ] && rm -f "$ACTUAL_LIST"
        exit 0
    fi
else
    log_message "正常下载模式: 处理所有样本..."
    log_message "总样本数: $TOTAL_COUNT"
    DOWNLOAD_COUNT=$TOTAL_COUNT
fi

log_message "使用 $JOBS 个并行任务下载 $DOWNLOAD_COUNT 个样本"

# 显示性能优化模式信息
if [ "$FAST_MODE" = true ]; then
    log_message "性能优化: 启用快速模式，优先使用状态文件判断"
else
    log_message "安全模式: 每次验证文件完整性"
fi

if [ "$JOBS" -eq 1 ]; then
    log_message "单任务模式，不使用 parallel"
    echo "单任务模式，不使用 parallel"
    while read -r acc; do
        [ -n "$acc" ] && fetch_one "$acc"
    done < "$ACTUAL_LIST"
else
    log_message "并行模式，使用 $JOBS 个任务"
    parallel -j "$JOBS" --joblog "$JOBLOG" fetch_one {} :::: "$ACTUAL_LIST"
fi

# 清理临时文件
[ -f "$ACTUAL_LIST" ] && [ "$ACTUAL_LIST" != "$SRA_LIST" ] && rm -f "$ACTUAL_LIST"

# 生成最终统计报告
log_message "下载任务完成，生成统计报告..."

SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

[ -f "$SUCCESS_LOG" ] && SUCCESS_COUNT=$(wc -l < "$SUCCESS_LOG")
[ -f "$FAILED_LOG" ] && FAILED_COUNT=$(wc -l < "$FAILED_LOG")
[ -f "$SKIPPED_LOG" ] && SKIPPED_COUNT=$(wc -l < "$SKIPPED_LOG")

log_message "========== 下载统计报告 =========="
log_message "总样本数: $TOTAL_COUNT"
log_message "成功下载: $SUCCESS_COUNT"
log_message "下载失败: $FAILED_COUNT"
log_message "跳过下载: $SKIPPED_COUNT"
log_message "=================================="

echo
echo "========== 下载完成 =========="
echo "总样本数: $TOTAL_COUNT"
echo "成功下载: $SUCCESS_COUNT"
echo "下载失败: $FAILED_COUNT"
echo "跳过下载: $SKIPPED_COUNT"
echo
echo "详细日志文件:"
echo "  成功日志: $SUCCESS_LOG"
echo "  失败日志: $FAILED_LOG"
echo "  跳过日志: $SKIPPED_LOG"
echo "  完整日志: $DOWNLOAD_LOG"
echo "  状态文件: $STATUS_FILE"
if [ "$FAILED_COUNT" -gt 0 ]; then
    echo "  失败列表: $FAILED_LIST"
    echo
    echo "如需重试失败的样本，请使用: $0 -r"
fi
echo "=============================="
