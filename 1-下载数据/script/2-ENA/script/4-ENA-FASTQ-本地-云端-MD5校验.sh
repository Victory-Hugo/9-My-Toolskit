#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
#  '
# 脚本功能说明：
# 本脚本用于对本地和云端的 MD5 校验结果进行比对，找出损坏或缺失的文件/目录，并批量删除这些无效数据。

# 主要流程：
# 1. 设置必要的路径和变量，包括 Python 解释器、脚本路径、MD5 文件、输出目录和下载目录。
# 2. 运行 Python 脚本，进行本地与云端 MD5 文件的比对，输出损坏或缺失的文件列表。
# 3. 检查损坏或缺失文件列表是否存在，若不存在则报错退出。
# 4. 遍历损坏或缺失文件列表，收集所有待删除的文件或目录路径。
# 5. 显示待删除项，提示用户确认是否删除。
# 6. 用户确认后，批量删除所有收集到的文件或目录，并输出删除结果。

# 注意事项：
# - 删除操作不可恢复，请务必确认待删除项。
# - 需保证相关路径和文件存在且有读写权限。
# - 依赖指定的 Python 环境和脚本，请提前配置好环境。
# '
# 配置区
PYTHON_PATH="/home/luolintao/miniconda3/envs/pyg/bin/python3"
BASE_DIR="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA"
PY_SCRIPT="$BASE_DIR/python/1-本地-云端-MD5校验.py"
LOCAL_MD5="$BASE_DIR/debug/md5.txt"
CLOUD_MD5="$BASE_DIR/debug/ERR_aDNA_MD5.txt"
OUTPUT_DIR="$BASE_DIR/debug/output"
DOWNLOAD_DIR="/mnt/d/迅雷下载/ENA"

# 函数：运行 MD5 比对
run_md5_compare() {
  mkdir -p "$OUTPUT_DIR"
  echo "==> 运行 MD5 对比脚本"
  "$PYTHON_PATH" "$PY_SCRIPT" \
    --local-file "$LOCAL_MD5" \
    --cloud-file "$CLOUD_MD5" \
    --outdir "$OUTPUT_DIR"
}

# 函数：收集待删除路径到数组 DELETE_LIST
collect_to_delete() {
  local damage_file="$OUTPUT_DIR/md5_损坏.txt"
  [[ -f "$damage_file" ]] || {
    echo "ERROR: 列表文件不存在：$damage_file" >&2
    exit 1
  }

  echo "收集待删除的文件/目录列表…"

  # 先把已有的所有样本（文件或目录）按 basename 建 map
  declare -A exist_map=()
  for dir in "$DOWNLOAD_DIR"/finished_*; do
    [[ -d "$dir" ]] || continue
    for item in "$dir"/*; do
      [[ -e "$item" ]] || continue
      exist_map["$(basename "$item")"]="$item"
    done
  done

  echo "正在匹配损坏的文件..."
  while read -r id; do
    [[ -z "$id" ]] && continue
    for name in "${!exist_map[@]}"; do
      if [[ "$name" == "$id"* ]]; then
        # 修正点：先缓存再 unset，避免 unbound variable
        path="${exist_map[$name]}"
        DELETE_LIST+=("$path")
        unset exist_map["$name"]
        echo "  找到待删除: $path"
      fi
    done
  done < "$damage_file"
}


# 函数：交互确认并删除
confirm_and_delete() {
  local n=${#DELETE_LIST[@]}
  echo "共收集到 $n 个待删除项："
  printf '  %s\n' "${DELETE_LIST[@]}"

  read -r -p "确认删除以上项目？输入 yes 删除，其它取消: " ans
  if [[ "$ans" != "yes" ]]; then
    echo "已取消删除。"
    return
  fi

  echo "开始删除…"
  for path in "${DELETE_LIST[@]}"; do
    if [[ -d "$path" ]]; then
      echo "  删除目录: $path"
      rm -rf "$path"
    elif [[ -f "$path" ]]; then
      echo "  删除文件: $path"
      rm -f "$path"
    fi
  done
  echo "删除完成，共删除 $n 项。"
}

# 函数：后续统计对比
stats_and_compare() {
  echo "[统计已下载名称...]"
  find "$DOWNLOAD_DIR" -type f -name '*fastq.gz' \
    | awk -F/ '{print $NF}' \
    | sed 's/\.fastq\.gz$//' \
    | sort -u > "$OUTPUT_DIR/Downloaded_IDs.txt"

  echo "[生成云端样本列表...]"
  awk -F'\t' '{print $1}' "$OUTPUT_DIR/ENA_cloud_md5.txt" \
    | sort -u > "$OUTPUT_DIR/Cloud_IDs.temp"

  echo "[比较已下载与云端列表，输出缺失...]"
  comm -13 "$OUTPUT_DIR/Downloaded_IDs.txt" "$OUTPUT_DIR/Cloud_IDs.temp" \
    > "$OUTPUT_DIR/md5_缺失.txt"

  rm -f "$OUTPUT_DIR/Cloud_IDs.temp"
  rm -f "$OUTPUT_DIR/Downloaded_IDs.txt"
  echo "[缺失样本列表已输出至 md5_缺失.txt]"
  cat "$OUTPUT_DIR/md5_缺失.txt" >> "$OUTPUT_DIR/md5_损坏.txt"
  sort -u "$OUTPUT_DIR/md5_损坏.txt" -o "$OUTPUT_DIR/md5_用我继续下载.temp"
  awk -v FS='_' '{print $1}' "$OUTPUT_DIR/md5_用我继续下载.temp" \
    | sort -u > "$OUTPUT_DIR/md5_用我继续下载.txt"
  rm -f "$OUTPUT_DIR/md5_用我继续下载.temp"
}

### 主流程
declare -a DELETE_LIST=()

run_md5_compare
collect_to_delete
confirm_and_delete
stats_and_compare