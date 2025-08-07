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
PYTHON_PATH="/home/luolintao/miniconda3/envs/pyg/bin/python3"
BASE_DIR="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA"
PY_SCRIPT="$BASE_DIR/python/1-本地-云端-MD5校验.py"
LOCAL_MD5_FILE="$BASE_DIR/debug/md5.txt"
CLOUD_MD5_FILE="$BASE_DIR/debug/ERR_aDNA_MD5.txt"
OUTPUT_DIR="$BASE_DIR/debug/output"
DOWNLOAD_DIR="/mnt/d/迅雷下载/ENA" 

mkdir -p "$OUTPUT_DIR"
echo "==> 运行 MD5 对比脚本"
"$PYTHON_PATH" "$PY_SCRIPT" \
  --local-file "$LOCAL_MD5_FILE" \
  --cloud-file "$CLOUD_MD5_FILE" \
  --outdir "$OUTPUT_DIR"

DAMAGE_LOSS_FILE="$OUTPUT_DIR/md5_损坏.txt"
if [[ ! -f "$DAMAGE_LOSS_FILE" ]]; then
  echo "ERROR: 列表文件不存在：$DAMAGE_LOSS_FILE" >&2
  exit 1
fi

echo "收集待删除的文件/目录列表…"
declare -a to_delete=()

# 优化方案：先获取所有已存在的目录，然后与损坏列表进行匹配
echo "正在扫描现有目录结构..."
declare -A existing_dirs=()
for subdir in "$DOWNLOAD_DIR"/finished_*; do
  [[ -d "$subdir" ]] || continue
  for item in "$subdir"/*; do
    [[ -e "$item" ]] || continue
    basename_item=$(basename "$item")
    existing_dirs["$basename_item"]="$item"
  done
done

echo "正在匹配损坏的文件..."
declare -A to_delete_set=()  # 使用关联数组去重
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  
  # 检查以该ID开头的所有文件/目录
  for key in "${!existing_dirs[@]}"; do
    if [[ "$key" == "${id}"* ]]; then
      path="${existing_dirs[$key]}"
      if [[ -z "${to_delete_set[$path]:-}" ]]; then
        to_delete_set["$path"]=1
        to_delete+=( "$path" )
        echo "找到待删除项: $path"
      fi
    fi
  done
done < "$DAMAGE_LOSS_FILE"

count=${#to_delete[@]}
if (( count == 0 )); then
  echo "未找到任何要删除的文件或目录。"
  exit 0
fi

echo "共找到 $count 个待删除项："
for p in "${to_delete[@]}"; do
  echo "  $p"
done

read -r -p "确认删除以上所有项目？输入 yes 删除，输入其他任何内容取消: " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "已取消删除。"
  exit 0
fi

echo "开始删除…"
for p in "${to_delete[@]}"; do
  if [[ -d "$p" ]]; then
    echo "Deleting directory: $p"
    rm -rf "$p"
  elif [[ -f "$p" ]]; then
    echo "Deleting file: $p"
    rm -f "$p"
  fi
done

echo "删除完成，共删除 $count 项。"
