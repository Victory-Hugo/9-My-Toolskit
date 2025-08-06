#!/usr/bin/env bash
set -euo pipefail

# —— 配置 —— 
LOCAL_MD5_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf/md5.txt"
REMOTE_MD5_FILE="/mnt/f/OneDrive/文档（共享）/4_古代DNA/ERR_aDNA_MD5.txt"

# —— 检查文件存在性 —— 
for f in "$LOCAL_MD5_FILE" "$REMOTE_MD5_FILE"; do
    [[ -f "$f" ]] || { echo "文件不存在：$f"; exit 1; }
done

# —— 1. 读入云端 MD5 映射： run_accession -> fastq_md5 —— 
declare -A remote_md5
while IFS=$'\t' read -r run_acc _ _ _ _ _ _ _ md5; do
    # 跳过表头
    [[ "$run_acc" == "run_accession" ]] && continue
    remote_md5["$run_acc"]="$md5"
done < "$REMOTE_MD5_FILE"

# —— 准备结果数组 —— 
complete=()
mismatch=()
local_only=()

# —— 2. 遍历本地 MD5 列表 —— 
#    本地文件格式：<md5><空格><本地全路径>
while read -r local_md5 local_path; do
    # 从路径提取 accession（去掉 .fastq 或 .fastq.gz）
    fname=$(basename "$local_path")
    acc=${fname%%.fastq*}
    if [[ -n "${remote_md5[$acc]:-}" ]]; then
        if [[ "$local_md5" == "${remote_md5[$acc]}" ]]; then
            complete+=("$acc")
        else
            mismatch+=("$acc")
        fi
    else
        local_only+=("$acc")
    fi
done < "$LOCAL_MD5_FILE"

# —— 3. 输出分类结果 —— 
echo
echo "=== 完整下载 (MD5 匹配) 共 ${#complete[@]} 条 ==="
printf '%s\n' "${complete[@]}"

echo
echo "=== 校验失败 (云端有，但 MD5 不一致) 共 ${#mismatch[@]} 条 ==="
printf '%s\n' "${mismatch[@]}"

echo
echo "=== 本地独有 (云端无此 accession) 共 ${#local_only[@]} 条 ==="
printf '%s\n' "${local_only[@]}"
