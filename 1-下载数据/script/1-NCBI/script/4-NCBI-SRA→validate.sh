: '
脚本功能：
    并行验证指定目录下所有 .sra 文件的完整性，使用 vdb-validate 工具。每个样本可重试多次，失败样本记录在日志文件。

参数说明：
    SRADIR      - .sra 文件所在的上级目录（需修改为实际路径）
    LOGDIR      - 日志输出目录，自动创建
    THREADS     - 并行处理的样本数
    RETRY       - 每个样本验证失败时的重试次数
    VALIDATE_CMD- 验证命令（默认 vdb-validate，需在 PATH 中）

主要流程：
    1. 创建日志目录。
    2. 定义 validate_one 函数：对单个 .sra 文件进行验证，失败时重试，最终失败则记录。
    3. 清空旧的失败列表。
    4. 使用 GNU parallel 并行调用 validate_one 验证所有 .sra 文件。
    5. 验证完成后，输出失败样本列表路径。

日志说明：
    每个样本生成独立的 .log（标准输出）和 .err（标准错误）日志文件。
    所有验证失败的样本 accession 记录在 failed_validation.list 文件中。

依赖：
    - vdb-validate 工具
    - GNU parallel
'
#!/usr/bin/env bash
set -euo pipefail

# 可修改路径
SRADIR="/mnt/g/鲍曼NC2025_1"            # .sra 所在上级目录
LOGDIR="$SRADIR/logs"
THREADS=1                                 # 并行样本数
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
