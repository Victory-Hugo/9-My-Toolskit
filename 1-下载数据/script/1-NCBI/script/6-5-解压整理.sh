# cd /mnt/d/迅雷下载/鲍曼组装/data/

# for dir in *_downloaded; do
#     new_name="${dir/_downloaded/}"
#     mv "$dir" "$new_name"
# done


# cd /mnt/d/迅雷下载/鲍曼组装/data/

# find $(pwd) -type f -name "README.md" | parallel --bar -j 8 rm {}

# cd /mnt/d/迅雷下载/鲍曼组装/data/

# find $(pwd) -type f -name "assembly_data_report.jsonl" | parallel --bar -j 8 rm {}


# cd /mnt/d/迅雷下载/鲍曼组装/data/

# find $(pwd) -type f -name "dataset_catalog.json" | parallel --bar -j 8 rm {}


# #!/usr/bin/env bash
# set -euo pipefail

# # 默认根目录（可用第一个非选项参数覆盖）
# ROOT="/mnt/d/迅雷下载/鲍曼组装/data"
# OVERWRITE=0
# BACKUP=0
# ROOT_SET=0

# # 解析参数：支持 --overwrite, --backup, 以及可选的根目录（可以在任意位置传）
# while [[ $# -gt 0 ]]; do
#   case "$1" in
#     --overwrite) OVERWRITE=1; shift ;;
#     --backup) BACKUP=1; shift ;;
#     --help|-h)
#       cat <<EOF
# 用法:
#   $0 [--overwrite] [--backup] [ROOT_DIRECTORY]

# 说明:
#   - 默认 ROOT_DIRECTORY = /mnt/d/迅雷下载/鲍曼组装/data
#   - 默认行为：遇到已存在的目标文件则跳过
#   - --overwrite : 如果目标已存在则直接覆盖
#   - --backup    : 如果目标已存在则先将目标备份为 <name>.bak.<timestamp> 再移动
# EOF
#       exit 0
#       ;;
#     *)
#       if [ $ROOT_SET -eq 0 ]; then
#         ROOT="$1"
#         ROOT_SET=1
#       fi
#       shift
#       ;;
#   esac
# done

# echo "根目录: $ROOT"
# if [ "$OVERWRITE" -eq 1 ]; then
#   echo "模式: 覆盖已存在目标 (--overwrite)"
# elif [ "$BACKUP" -eq 1 ]; then
#   echo "模式: 备份已存在目标 (--backup)"
# else
#   echo "模式: 跳过已存在目标 (默认)"
# fi
# echo

# # 查找并重命名
# find "$ROOT" -type f -name 'cds_from_genomic.fna' -print0 |
# while IFS= read -r -d '' file; do
#   dir="$(dirname "$file")"
#   parent="$(basename "$dir")"
#   newpath="$dir/${parent}_CDS.fna"

#   if [ -e "$newpath" ]; then
#     if [ "$OVERWRITE" -eq 1 ]; then
#       echo "OVERWRITE: '$file' -> '$newpath' (覆盖已有文件)"
#       mv -f -- "$file" "$newpath"
#     elif [ "$BACKUP" -eq 1 ]; then
#       bak="${newpath}.bak.$(date +%s)"
#       echo "BACKUP: 先将已有目标 '$newpath' 备份为 '$bak'，再移动"
#       mv -- "$newpath" "$bak"
#       mv -v -- "$file" "$newpath"
#     else
#       echo "SKIP (目标已存在): '$file' -> '$newpath'"
#       continue
#     fi
#   else
#     mv -v -- "$file" "$newpath"
#   fi
# done

# #!/usr/bin/env bash
# set -euo pipefail

# # 默认根目录（可用第一个非选项参数覆盖）
# ROOT="/mnt/d/迅雷下载/鲍曼组装/data"
# OVERWRITE=0
# BACKUP=0
# ROOT_SET=0

# # 解析参数：支持 --overwrite, --backup, 以及可选的根目录（可以在任意位置传）
# while [[ $# -gt 0 ]]; do
#   case "$1" in
#     --overwrite) OVERWRITE=1; shift ;;
#     --backup) BACKUP=1; shift ;;
#     --help|-h)
#       cat <<EOF
# 用法:
#   $0 [--overwrite] [--backup] [ROOT_DIRECTORY]

# 说明:
#   - 默认 ROOT_DIRECTORY = /mnt/d/迅雷下载/鲍曼组装/data
#   - 脚本会在 ROOT 下查找名为 genomic.gff 的文件并重命名为 <父目录名>.gff（保留在同一目录）
#   - 默认行为：遇到已存在的目标文件则跳过（不覆盖）
#   - --overwrite : 如果目标已存在则直接覆盖
#   - --backup    : 如果目标已存在则先将目标备份为 <name>.gff.bak.<timestamp> 再移动
# EOF
#       exit 0
#       ;;
#     *)
#       if [ $ROOT_SET -eq 0 ]; then
#         ROOT="$1"
#         ROOT_SET=1
#       fi
#       shift
#       ;;
#   esac
# done

# echo "根目录: $ROOT"
# if [ "$OVERWRITE" -eq 1 ]; then
#   echo "模式: 覆盖已存在目标 (--overwrite)"
# elif [ "$BACKUP" -eq 1 ]; then
#   echo "模式: 备份已存在目标 (--backup)"
# else
#   echo "模式: 跳过已存在目标 (默认)"
# fi
# echo

# # 查找并重命名 genomic.gff
# find "$ROOT" -type f -name 'genomic.gff' -print0 |
# while IFS= read -r -d '' file; do
#   dir="$(dirname "$file")"
#   parent="$(basename "$dir")"
#   newpath="$dir/${parent}.gff"

#   if [ -e "$newpath" ]; then
#     if [ "$OVERWRITE" -eq 1 ]; then
#       echo "OVERWRITE: '$file' -> '$newpath' (覆盖已有文件)"
#       mv -f -- "$file" "$newpath"
#     elif [ "$BACKUP" -eq 1 ]; then
#       bak="${newpath}.bak.$(date +%s)"
#       echo "BACKUP: 先将已有目标 '$newpath' 备份为 '$bak'，再移动"
#       mv -- "$newpath" "$bak"
#       mv -v -- "$file" "$newpath"
#     else
#       echo "SKIP (目标已存在): '$file' -> '$newpath'"
#       continue
#     fi
#   else
#     mv -v -- "$file" "$newpath"
#   fi
# done

# #!/usr/bin/env bash
# set -euo pipefail

# # 默认根目录（可用第一个非选项参数覆盖）
# ROOT="/mnt/d/迅雷下载/鲍曼组装/data"
# OVERWRITE=0
# BACKUP=0
# ROOT_SET=0

# # 解析参数：支持 --overwrite, --backup, 以及可选的根目录（可以在任意位置传）
# while [[ $# -gt 0 ]]; do
#   case "$1" in
#     --overwrite) OVERWRITE=1; shift ;;
#     --backup) BACKUP=1; shift ;;
#     --help|-h)
#       cat <<EOF
# 用法:
#   $0 [--overwrite] [--backup] [ROOT_DIRECTORY]

# 说明:
#   - 默认 ROOT_DIRECTORY = /mnt/d/迅雷下载/鲍曼组装/data
#   - 脚本会在 ROOT 下查找所有以 .fna 结尾且 NOT 以 _CDS.fna 结尾的文件
#   - 每个匹配文件将被重命名为 <父目录名>.fasta，保留在同一目录
#   - 默认行为：若目标已存在则跳过（避免覆盖）
#   - --overwrite : 如果目标已存在则直接覆盖
#   - --backup    : 如果目标已存在则先将目标备份为 <name>.fasta.bak.<timestamp> 再移动
# EOF
#       exit 0
#       ;;
#     *)
#       if [ $ROOT_SET -eq 0 ]; then
#         ROOT="$1"
#         ROOT_SET=1
#       fi
#       shift
#       ;;
#   esac
# done

# echo "根目录: $ROOT"
# if [ "$OVERWRITE" -eq 1 ]; then
#   echo "模式: 覆盖已存在目标 (--overwrite)"
# elif [ "$BACKUP" -eq 1 ]; then
#   echo "模式: 备份已存在目标 (--backup)"
# else
#   echo "模式: 跳过已存在目标 (默认)"
# fi
# echo

# # 查找并重命名：所有 *.fna 且不以 _CDS.fna 结尾
# find "$ROOT" -type f -name '*.fna' ! -name '*_CDS.fna' -print0 |
# while IFS= read -r -d '' file; do
#   dir="$(dirname "$file")"
#   parent="$(basename "$dir")"
#   newpath="$dir/${parent}.fasta"

#   # 如果文件本身已经就是目标名称（极少见，.fna -> .fasta 仍需移动），继续按规则处理
#   if [ -e "$newpath" ]; then
#     if [ "$OVERWRITE" -eq 1 ]; then
#       echo "OVERWRITE: '$file' -> '$newpath' (覆盖已有文件)"
#       mv -f -- "$file" "$newpath"
#     elif [ "$BACKUP" -eq 1 ]; then
#       bak="${newpath}.bak.$(date +%s)"
#       echo "BACKUP: 先将已有目标 '$newpath' 备份为 '$bak'，再移动"
#       mv -- "$newpath" "$bak"
#       mv -v -- "$file" "$newpath"
#     else
#       echo "SKIP (目标已存在): '$file' -> '$newpath'"
#       continue
#     fi
#   else
#     mv -v -- "$file" "$newpath"
#   fi
# done

#!/usr/bin/env bash
set -euo pipefail

ROOT="/mnt/d/迅雷下载/鲍曼组装/data"
OVERWRITE=0
BACKUP=0
ROOT_SET=0

usage() {
  cat <<EOF
用法:
  $0 [--overwrite] [--backup] [ROOT_DIRECTORY]

说明:
  - 默认 ROOT_DIRECTORY = /mnt/d/迅雷下载/鲍曼组装/data
  - 对于每个样本目录 (ROOT/*)，若存在 ncbi_dataset/data/<inner>/，
    则把 <inner> 中的所有内容移动到样本目录 (即上层)，
    然后尝试删除空目录 ncbi_dataset/data/ 和 ncbi_dataset/（仅当为空时删除）。
  - 默认：遇到目标已存在则跳过（不覆盖）
  - --overwrite : 若目标已存在则直接覆盖
  - --backup    : 若目标已存在则先将目标备份为 <name>.bak.<timestamp> 再移动
EOF
}

# 参数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
    --overwrite) OVERWRITE=1; shift ;;
    --backup) BACKUP=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      if [ $ROOT_SET -eq 0 ]; then
        ROOT="$1"
        ROOT_SET=1
      fi
      shift
      ;;
  esac
done

echo "根目录: $ROOT"
if [ "$OVERWRITE" -eq 1 ]; then
  echo "模式: 覆盖已存在目标 (--overwrite)"
elif [ "$BACKUP" -eq 1 ]; then
  echo "模式: 备份已存在目标 (--backup)"
else
  echo "模式: 跳过已存在目标 (默认)"
fi
echo

# 处理每个样本目录
shopt -s nullglob
for sample in "$ROOT"/*; do
  [ -d "$sample" ] || continue

  data_base="$sample/ncbi_dataset/data"
  if [ ! -d "$data_base" ]; then
    # 没有 ncbi_dataset/data，跳过
    continue
  fi

  # 遍历 data 下的每个 inner 目录（通常是与 sample 同名的子目录）
  found_any_inner=0
  for inner in "$data_base"/*; do
    [ -d "$inner" ] || continue
    found_any_inner=1
    echo "处理: inner='$inner' -> sample='$sample'"

    # 将 inner 下的所有内容逐个移动到 sample
    # 使用 find 保证能处理大量文件和特殊名字
    find "$inner" -mindepth 1 -maxdepth 1 -print0 |
    while IFS= read -r -d '' item; do
      name="$(basename "$item")"
      dest="$sample/$name"

      if [ -e "$dest" ]; then
        if [ "$OVERWRITE" -eq 1 ]; then
          echo "  OVERWRITE: '$item' -> '$dest' (覆盖已有目标)"
          # 若目标存在且是目录，先移除或覆盖（mv -f 会将 item 移入 dest/，这通常不是我们想要的）
          # 为简单起见，先删除目标再移动（如果目标是目录且 OVERWRITE=1，谨慎：会 rm -rf）
          if [ -d "$dest" ]; then
            echo "    注意: 目标是目录，OVERWRITE 模式下将递归删除目标目录 '$dest'"
            rm -rf -- "$dest"
          else
            rm -f -- "$dest"
          fi
          mv -v -- "$item" "$sample/"
        elif [ "$BACKUP" -eq 1 ]; then
          bak="${dest}.bak.$(date +%s)"
          echo "  BACKUP: 先将已有目标 '$dest' 备份为 '$bak'，然后移动 '$item'"
          mv -- "$dest" "$bak"
          mv -v -- "$item" "$sample/"
        else
          echo "  SKIP (目标已存在): '$item' -> '$dest'"
          continue
        fi
      else
        # 目标不存在，直接移动
        mv -v -- "$item" "$sample/"
      fi
    done

    # 尝试删除 now-empty inner 目录（若非空则保留并打印警告）
    if rmdir "$inner" 2>/dev/null; then
      echo "  已删除空目录: $inner"
    else
      echo "  注意: 目录非空或删除失败，保留: $inner"
    fi
  done

  if [ "$found_any_inner" -eq 0 ]; then
    # 没有 inner 子目录
    continue
  fi

  # 尝试删除 data_base（ncbi_dataset/data）与 ncbi_dataset（自内向外）
  if rmdir "$data_base" 2>/dev/null; then
    echo "  已删除空目录: $data_base"
  else
    echo "  注意: $data_base 非空或删除失败，保留"
  fi

  parent_nd="$sample/ncbi_dataset"
  if rmdir "$parent_nd" 2>/dev/null; then
    echo "  已删除空目录: $parent_nd"
  else
    echo "  注意: $parent_nd 非空或删除失败，保留"
  fi

done

echo
echo "全部完成。"
