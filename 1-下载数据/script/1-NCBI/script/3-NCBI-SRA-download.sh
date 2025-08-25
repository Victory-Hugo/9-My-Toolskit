: '
脚本名称: 6-NCBI-SRA-download.sh
功能描述:
    本脚本用于批量下载 NCBI SRA 数据，支持断点续传和失败重试，适用于大规模数据下载任务。
    主要特性包括：
      - 并行下载（依赖 GNU parallel）
      - 每个 accession 号可配置最大重试次数
      - 下载失败的 accession 号会被记录，便于后续处理
      - 跳过已成功下载的数据，避免重复下载

使用说明:
    1. 修改脚本中的以下参数以适应你的环境：
        - SRA_LIST: 包含 SRA accession 号的文本文件路径，每行一个 accession
        - PREFETCH: prefetch 可执行文件的绝对路径
        - OUTDIR: 下载数据的输出目录
        - JOBS: 并行任务数（根据机器性能调整）
        - MAX_RETRY: 每个 accession 最大重试次数
    2. 确保已安装 GNU parallel 和 sratoolkit，并配置好环境变量
    3. 运行脚本即可自动批量下载 SRA 数据

依赖:
    - GNU parallel
    - sratoolkit（prefetch 工具）

输出:
    - 下载的 SRA 文件保存在 OUTDIR 目录下
    - 下载失败的 accession 号记录在 $FAILED_LIST 文件中
    - parallel 运行日志保存在 $JOBLOG 文件中

注意事项:
    - 若某个 accession 多次下载失败，请检查网络或 SRA 号有效性
    - 脚本会自动跳过已存在的 SRA 文件，支持断点续传
    - 失败列表可用于后续单独重试或人工检查

作者: （请填写作者信息）
更新时间: （请填写日期）
'
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
unset http_proxy
unset https_proxy
# PROJ="鲍曼NC2025_1"
SRA_LIST="/mnt/g/鲍曼NC2025_6/conf/download_6.txt" #? 格式：每行一个 SRA/ERR/DRR 号

#* prefetch 可执行文件路径
PREFETCH="/mnt/e/Scientifc_software/sratoolkit.3.1.1-ubuntu64/bin/prefetch" #! 不知道如何配置的请查看`1-下载数据/script/1-NCBI/markdown/1-NCBI-SRA-代码使用说明.md`
# OUTDIR="/mnt/g/${PROJ}/" #* 下载输出目录
OUTDIR="/mnt/g/鲍曼NC2025_6/data/"

mkdir -p "$OUTDIR" || { echo "无法创建输出目录: $OUTDIR"; exit 1; }
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