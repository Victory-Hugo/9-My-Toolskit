#!/usr/bin/env bash
# SRA 批量下载脚本（改进版）
# 依赖：GNU parallel, prefetch
# 主要改动：
#   1) 去掉 parallel 的 --halt soon,fail=1，避免因单条失败而整体停止
#   2) 内置重试逻辑，可配置最大重试次数
#   3) 记录永久失败的 accession 号，便于后续处理

####################################
# 基本参数                          #
####################################
#TODO : 修改以下参数以适应你的环境
#* SRA 列表文件路径
#* 格式：每行一个 accession 号
SRA_LIST="/mnt/f/OneDrive/文档（共享）/4_古代DNA/SRR_aDNA.txt"
#* prefetch 可执行文件路径
#! 不知道如何配置的请查看`1-下载数据/script/1-NCBI/markdown/1-NCBI-SRA-代码使用说明.md`
PREFETCH="/mnt/e/Scientifc_software/sratoolkit.3.1.1-ubuntu64/bin/prefetch"
#* 下载输出目录
OUTDIR="/mnt/d/迅雷下载/NCBI/"

#* 下载配置
JOBS=4               # 并行任务数
MAX_RETRY=3          # 每个 accession 最多重试次数
FAILED_LIST="$OUTDIR/failed.list"   # 永久失败列表
JOBLOG="$OUTDIR/joblog.txt"         # parallel 运行日志
####################################

# 检查依赖
command -v parallel >/dev/null 2>&1 || { echo "请先安装 GNU parallel"; exit 1; }
[ -x "$PREFETCH" ] || { echo "prefetch 路径无效: $PREFETCH"; exit 1; }
[ -f "$SRA_LIST" ] || { echo "SRA 列表文件不存在: $SRA_LIST"; exit 1; }

# 下载函数
fetch_one() {
    acc="$1"

    # 若已下载完成（prefetch 默认生成 $acc/$acc.sra）
    if [ -f "$OUTDIR/$acc/$acc.sra" ] || ls "$OUTDIR/$acc"/*.sra >/dev/null 2>&1; then
        echo "$acc 已存在，跳过"
        return 0
    fi

    echo "开始下载 $acc ..."
    for ((i=1; i<=MAX_RETRY; i++)); do
        "$PREFETCH" --output-directory "$OUTDIR" "$acc" && break
        echo "$acc 第 $i/$MAX_RETRY 次下载失败，重试中…" >&2
        sleep 10
    done

    # 最终检查
    if ! ls "$OUTDIR/$acc"/*.sra >/dev/null 2>&1; then
        echo "$acc 经过 $MAX_RETRY 次尝试仍失败，记录到 $FAILED_LIST" >&2
        echo "$acc" >> "$FAILED_LIST"
    fi
    # 始终返回 0，以免 parallel 因失败而早停
    return 0
}

export -f fetch_one
export PREFETCH OUTDIR MAX_RETRY FAILED_LIST

# 并行运行
mkdir -p "$OUTDIR"
: > "$FAILED_LIST"     # 清空旧的失败记录
parallel -j "$JOBS" --joblog "$JOBLOG" fetch_one {} :::: "$SRA_LIST"

echo "全部任务完成。失败列表见 $FAILED_LIST（如有）。"