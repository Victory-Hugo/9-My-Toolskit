#!/usr/bin/env bash
set -euo pipefail

# 可修改路径
SRADIR="/mnt/d/迅雷下载/NCBI"            # .sra 所在上级目录
LOGDIR="$SRADIR/logs"
THREADS=4                                 # 并行样本数
RETRY=2                                   # 每个样本验证重试次数

VALIDATE_CMD="vdb-validate"               # 假定在 PATH 中

mkdir -p "$LOGDIR"

validate_one() {
    sra_path="$1"
    acc=$(basename "$sra_path" .sra)
    stdout_log="$LOGDIR/${acc}.log"
    stderr_log="$LOGDIR/${acc}.err"
    fail_list="$LOGDIR/failed_validation.list"

    echo "=== 开始验证 $acc ===" >>"$stdout_log"

    if ! command -v "$VALIDATE_CMD" >/dev/null 2>&1; then
        echo "错误：找不到 $VALIDATE_CMD" >&2
        exit 1
    fi

    local attempt=1
    while [ "$attempt" -le "$RETRY" ]; do
        echo "验证 $acc 第 $attempt 次尝试" >>"$stdout_log"
        if "$VALIDATE_CMD" "$sra_path" >>"$stdout_log" 2>>"$stderr_log"; then
            echo "$acc 验证通过" >>"$stdout_log"
            return 0
        else
            echo "$acc 第 $attempt 次验证失败" >>"$stderr_log"
            attempt=$((attempt + 1))
            sleep 2
        fi
    done

    echo "$acc 经过 $RETRY 次尝试仍验证失败" >>"$stderr_log"
    echo "$acc" >>"$fail_list"
    return 1
}

export -f validate_one
export LOGDIR VALIDATE_CMD RETRY

# 清空旧失败记录
: > "$LOGDIR/failed_validation.list"

# 找所有 .sra 并并行验证
find "$SRADIR" -type f -name "*.sra" | \
    parallel -j "$THREADS" validate_one {}

echo "验证完成。失败列表（若有）在 $LOGDIR/failed_validation.list"
