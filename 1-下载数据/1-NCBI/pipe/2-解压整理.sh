#!/usr/bin/env bash
set -euo pipefail
#! 功能说明：
#! 1. 自动解压ZIP文件到单独文件夹
#! 2. 重命名和整理文件结构
#! 3. 创建树状目录结构避免文件夹过多
#! 使用方法: ./2-解压整理.sh [ROOT_DIRECTORY] [--overwrite] [--backup]
#*==========解压后示例如下==========
# ├── GCF_003063885.1_downloaded
# │   ├── README.md
# │   ├── md5sum.txt
# │   └── ncbi_dataset
# │       └── data
# │           ├── GCF_003063885.1
# │           │   ├── GCF_003063885.1_ASM306388v1_genomic.fna
# │           │   ├── cds_from_genomic.fna
# │           │   └── genomic.gff
# │           ├── assembly_data_report.jsonl
# │           └── dataset_catalog.json
#*============================
# 默认工作目录
ROOT="/mnt/c/Users/Administrator/Desktop/download"
OVERWRITE=0
BACKUP=0
ROOT_SET=0
MAX_FILES_PER_DIR=5000

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --overwrite) OVERWRITE=1; shift ;;
    --backup) BACKUP=1; shift ;;
    --max-files) shift; MAX_FILES_PER_DIR="$1"; shift ;;
    --help|-h)
      echo "Usage: $0 [ROOT_DIRECTORY] [--overwrite] [--backup] [--max-files N]"
      echo "  ROOT_DIRECTORY: 下载目录路径 (默认: $ROOT)"
      echo "  --overwrite: 覆盖已存在的文件"
      echo "  --backup: 备份已存在的文件"
      echo "  --max-files N: 每个目录最大文件数 (默认: 5000)"
      exit 0 ;;
    *) if [ $ROOT_SET -eq 0 ]; then ROOT="$1"; ROOT_SET=1; fi; shift ;;
  esac
done

echo "开始处理目录: $ROOT"
echo "每目录最大文件数: $MAX_FILES_PER_DIR"

############################
# 1. 解压ZIP文件
############################
echo "步骤1: 解压ZIP文件..."
zip_count=0
extracted_count=0

# 检查是否有ZIP文件
shopt -s nullglob  # 让glob模式在没有匹配时返回空
zip_files=("$ROOT"/*.zip "$ROOT"/*_downloaded.zip)
shopt -u nullglob

if [ ${#zip_files[@]} -eq 0 ]; then
  echo "没有找到ZIP文件，跳过解压步骤"
else
  echo "找到 ${#zip_files[@]} 个ZIP文件"
  
  for zip_file in "${zip_files[@]}"; do
    [ -f "$zip_file" ] || continue
    ((zip_count++))
    
    # 获取不含扩展名的文件名
    if [[ "$zip_file" == *"_downloaded.zip" ]]; then
      basename=$(basename "$zip_file" _downloaded.zip)
    else
      basename=$(basename "$zip_file" .zip)
    fi
    extract_dir="$ROOT/${basename}"
    
    # 如果目录已存在，跳过
    if [ -d "$extract_dir" ]; then
      echo "跳过已存在的目录: $basename"
      continue
    fi
    
    # 解压文件
    echo "解压: $basename"
    if unzip -q "$zip_file" -d "$extract_dir"; then
      # 删除原zip文件以节省空间
      rm "$zip_file"
      ((extracted_count++))
    else
      echo "错误: 解压 $basename 失败"
      continue
    fi
  
    
    # 每100个文件显示一次进度
    if ((extracted_count % 100 == 0)); then
      echo "已解压: $extracted_count/$zip_count"
    fi
  done
  
  echo "解压完成: 共处理 $zip_count 个ZIP文件，解压 $extracted_count 个"
fi

############################
# 2. 重命名 *_downloaded 目录
############################
for dir in "$ROOT"/*_downloaded; do
  [ -d "$dir" ] || continue
  new_name="${dir/_downloaded/}"
  mv "$dir" "$new_name"
done

############################
# 3. 删除无用文件 (并行)
############################
echo "步骤3: 删除无用文件..."
cd "$ROOT"
for pat in "README.md" "md5sum.txt" "assembly_data_report.jsonl" "dataset_catalog.json"; do
  find "$ROOT" -type f -name "$pat" | parallel --bar -j 8 rm {}
done


##################################################
# 3. 统一重命名工具函数
##################################################
rename_with_policy() {
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    if [ "$OVERWRITE" -eq 1 ]; then
      echo "OVERWRITE: '$src' -> '$dst'"
      mv -f -- "$src" "$dst"
    elif [ "$BACKUP" -eq 1 ]; then
      bak="${dst}.bak.$(date +%s)"
      echo "BACKUP: '$dst' -> '$bak'"
      mv -- "$dst" "$bak"
      mv -v -- "$src" "$dst"
    else
      echo "SKIP (目标已存在): '$src' -> '$dst'"
    fi
  else
    mv -v -- "$src" "$dst"
  fi
}
##################################################


############################
# 4. 重命名 cds_from_genomic.fna -> <parent>_CDS.fna
############################
echo "步骤4: 重命名CDS文件..."

find "$ROOT" -type f -name 'cds_from_genomic.fna' -print0 |
while IFS= read -r -d '' file; do
  dir="$(dirname "$file")"
  parent="$(basename "$dir")"
  newpath="$dir/${parent}_CDS.fna"
  rename_with_policy "$file" "$newpath"
done


############################
# 5. 重命名 genomic.gff -> <parent>.gff
############################
echo "步骤5: 重命名GFF文件..."
find "$ROOT" -type f -name 'genomic.gff' -print0 |
while IFS= read -r -d '' file; do
  dir="$(dirname "$file")"
  parent="$(basename "$dir")"
  newpath="$dir/${parent}.gff"
  rename_with_policy "$file" "$newpath"
done


############################
# 6. 重命名 *.fna -> <parent>.fasta (排除 *_CDS.fna)
############################
echo "步骤6: 重命名FASTA文件..."
find "$ROOT" -type f -name '*.fna' ! -name '*_CDS.fna' -print0 |
while IFS= read -r -d '' file; do
  dir="$(dirname "$file")"
  parent="$(basename "$dir")"
  newpath="$dir/${parent}.fasta"
  rename_with_policy "$file" "$newpath"
done


############################
# 7. 重命名 protein.faa -> <parent>.faa
############################
echo "步骤7: 重命名蛋白质文件..."
find "$ROOT" -type f -name 'protein.faa' -print0 |
while IFS= read -r -d '' file; do
  dir="$(dirname "$file")"
  parent="$(basename "$dir")"
  newpath="$dir/${parent}.faa"
  rename_with_policy "$file" "$newpath"
done


############################
# 8. 展开 ncbi_dataset/data 目录结构
############################
echo "步骤8: 展开NCBI数据集目录结构..."
for sample in "$ROOT"/*; do
  [ -d "$sample" ] || continue
  data_base="$sample/ncbi_dataset/data"
  [ -d "$data_base" ] || continue

  for inner in "$data_base"/*; do
    [ -d "$inner" ] || continue
    echo "处理 inner='$inner'"
    find "$inner" -mindepth 1 -maxdepth 1 -print0 |
    while IFS= read -r -d '' item; do
      name="$(basename "$item")"
      dest="$sample/$name"
      rename_with_policy "$item" "$dest"
    done
    rmdir "$inner" 2>/dev/null || echo "保留非空目录: $inner"
  done

  rmdir "$data_base" 2>/dev/null || echo "保留非空目录: $data_base"
  rmdir "$sample/ncbi_dataset" 2>/dev/null || echo "保留非空目录: $sample/ncbi_dataset"
done

############################
# 9. 创建树状目录结构
############################
echo "步骤9: 创建树状目录结构..."

# 创建临时工作目录
TEMP_ORGANIZED="${ROOT}_organized_$(date +%s)"
mkdir -p "$TEMP_ORGANIZED"

# 获取所有需要整理的目录
dirs_to_organize=()
for item in "$ROOT"/*; do
  [ -d "$item" ] || continue
  # 跳过临时目录
  [[ "$(basename "$item")" == *"_organized_"* ]] && continue
  dirs_to_organize+=("$item")
done

total_dirs=${#dirs_to_organize[@]}
echo "需要整理的目录总数: $total_dirs"

if [ $total_dirs -eq 0 ]; then
  rmdir "$TEMP_ORGANIZED"
  echo "没有需要整理的目录。"
else
  # 计算需要的层级结构
  if [ $total_dirs -le $MAX_FILES_PER_DIR ]; then
    # 不需要分层，直接移动
    echo "目录数量未超过限制，直接移动到新结构"
    for dir in "${dirs_to_organize[@]}"; do
      mv "$dir" "$TEMP_ORGANIZED/"
    done
  else
    # 需要分层处理
    echo "目录数量超过限制，创建分层结构"
    
    # 函数：创建分层目录路径
    create_nested_path() {
      local index=$1
      local max_per_dir=$2
      local level1=$((index / max_per_dir))
      local level2=$((index % max_per_dir))
      
      # 格式化目录名，使用4位数字确保排序正确
      local dir1=$(printf "%04d-%04d" $((level1 * max_per_dir)) $(((level1 + 1) * max_per_dir - 1)))
      echo "$dir1"
    }
    
    # 整理目录
    for i in "${!dirs_to_organize[@]}"; do
      dir="${dirs_to_organize[$i]}"
      nested_path=$(create_nested_path $i $MAX_FILES_PER_DIR)
      target_dir="$TEMP_ORGANIZED/$nested_path"
      
      # 创建目标目录
      mkdir -p "$target_dir"
      
      # 移动目录
      mv "$dir" "$target_dir/"
      
      # 显示进度
      if (((i + 1) % 1000 == 0)) || ((i + 1 == total_dirs)); then
        echo "已整理: $((i + 1))/$total_dirs"
      fi
    done
  fi
  
  # 替换原目录
  BACKUP_DIR="${ROOT}_backup_$(date +%s)"
  echo "备份原目录到: $BACKUP_DIR"
  mv "$ROOT" "$BACKUP_DIR"
  mv "$TEMP_ORGANIZED" "$ROOT"
  
  echo "树状结构创建完成！"
  echo "原目录备份: $BACKUP_DIR"
  echo "新目录结构: $ROOT"
  
  # 显示新结构统计
  echo "新目录结构统计:"
  find "$ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | xargs echo "  一级目录数:"
  find "$ROOT" -mindepth 2 -maxdepth 2 -type d | wc -l | xargs echo "  二级目录数:"
fi

echo "全部完成！"
