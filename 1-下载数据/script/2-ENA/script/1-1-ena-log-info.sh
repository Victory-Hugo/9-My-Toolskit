#!/bin/bash
: '
脚本功能说明：
本脚本用于处理ENA数据下载日志，自动提取成功和失败的样本编号，并整理未完成的样本列表，同时将已成功下载的样本文件夹移动到指定目录。

主要功能步骤：
1. 从日志文件中提取下载成功的样本编号，保存到SUCCESS_LIST_FILE。
2. 从日志文件中提取下载失败的样本编号，保存到INCOMPLETE_LIST_FILE。
3. 通过比较全部样本编号与成功编号，补充未完成样本编号到INCOMPLETE_LIST_FILE。
4. 将所有已成功下载的样本文件夹从原始目录移动到目标目录（finished_1），便于后续管理。

变量说明：
- LOG_FILE：ENA下载日志文件路径。
- ALL_LIST_FILE：全部样本编号列表文件路径。
- INCOMPLETE_LIST_FILE：输出未完成样本编号列表路径。
- SUCCESS_LIST_FILE：输出成功样本编号列表路径。
- SRC_ROOT：已下载样本文件夹的根目录。
- DST_ROOT：成功样本文件夹的目标根目录。

使用说明：
- 请根据实际情况修改LOG_FILE、ALL_LIST_FILE、INCOMPLETE_LIST_FILE、SUCCESS_LIST_FILE、SRC_ROOT和DST_ROOT的路径。
- 运行脚本前请确保相关目录和文件存在，且有足够权限进行文件操作。
# '
# #!需要注意，我发现一些在log文件中被记录为'could not be completed'的样本编号，实际上是可能已经完成了;
# #!但是ena 的愚蠢的下载器会认为这些样本没有下载完成
# #TODO输入文件
# LOG_FILE="/mnt/d/迅雷下载/ENA/logs/2025-08-04_20-34-15_app.log" #TODO 替换为实际的日志文件路径
# ALL_LIST_FILE="/mnt/f/OneDrive/文档（共享）/4_古代DNA/ERR_aDNA.txt" #TODO 替换为实际的样本编号列表路径

# #TODO输出文件
# INCOMPLETE_LIST_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf/Incomplete.list.txt" #TODO 替换为输出路径
# SUCCESS_LIST_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf/Success.list.txt" #TODO 替换为输出路径

# # 提取日志中的成功信息并格式化输出

# echo "提取成功的样本编号..."
# grep 'SUCCESSFUL' \
#     "$LOG_FILE" |\
#     awk -v FS=':' '{print $5}' |\
#     awk -v FS='fastq' '{print $1}' |\
#     awk -v FS='_' '{print $1}' |\
#     awk -v FS='.' '{print $1}' |\
#     sort -u > "$SUCCESS_LIST_FILE"
# echo "成功的样本编号已保存到 [$SUCCESS_LIST_FILE]"

# echo "提取失败的样本编号..."
# grep 'could not be completed' "$LOG_FILE" |\
#     awk -v FS='file ' '{print $2}' |\
#     awk -v FS='_' '{print $1}' |\
#     awk -v FS='.' '{print $1}' |\
#     sort -u > "$INCOMPLETE_LIST_FILE"
# echo "失败的样本编号已保存到 [$INCOMPLETE_LIST_FILE]"


# # 使用comm命令比较成功编号和总的编号列表
# # 比较 ALL_LIST_FILE 与 SUCCESS_LIST_FILE 的差集，保存到 INCOMPLETE_LIST_FILE
# # 取差集：ALL - SUCCESS → 追加到 INCOMPLETE
# comm -23 <(sort "$ALL_LIST_FILE") <(sort "$SUCCESS_LIST_FILE") \
#     >> "$INCOMPLETE_LIST_FILE"
# sort -u "$INCOMPLETE_LIST_FILE" -o "$INCOMPLETE_LIST_FILE"
# echo "  ⇒ 差集（未完成样本编号）已保存到 [$INCOMPLETE_LIST_FILE]"

# 将已经下载成功的文件所在的文件夹放到/mnt/d/迅雷下载/ENA/finished_1
# 刚下载好的文件目前在：/mnt/d/迅雷下载/ENA/reads_fastq：
# 例如/mnt/d/迅雷下载/ENA/reads_fastq/ERR2111937
# /mnt/d/迅雷下载/ENA/reads_fastq/ERR2111938
# /mnt/d/迅雷下载/ENA/reads_fastq/ERR2111939
# /mnt/d/迅雷下载/ENA/reads_fastq/ERR2111940
# /mnt/d/迅雷下载/ENA/reads_fastq/ERR2111941

# 需要读取${SUCCESS_LIST_FILE}中的编号，例如:
# ERR2111941
# ERR2111945
# ERR2112079
# ERR2307920
# 将这些编号对应的文件夹移动到/mnt/d/迅雷下载/ENA/finished_1
# ====================================================================
# 将已下载成功的样本文件夹移动到 finished_1
# 已下载的原始文件夹路径：/mnt/d/迅雷下载/ENA/reads_fastq/{样本编号}
# 目标文件夹：/mnt/d/迅雷下载/ENA/finished_1/{样本编号}
# ====================================================================

SRC_ROOT="/mnt/d/迅雷下载/ENA/reads_fastq"
DST_ROOT="/mnt/d/迅雷下载/ENA/finished_1"

echo "开始移动成功样本文件夹到 [$DST_ROOT] ..."
# 确保目标根目录存在
mkdir -p "$DST_ROOT"

# 逐行读取成功列表，移动对应文件夹
while IFS= read -r sample_id; do
  src_dir="$SRC_ROOT/$sample_id"
  dst_dir="$DST_ROOT/$sample_id"
  if [[ -d "$src_dir" ]]; then
    echo "  ➜ Moving $src_dir → $dst_dir"
    mv "$src_dir" "$dst_dir"
  else
    echo "  ⚠️  源文件夹不存在：$src_dir，跳过"
  fi
done < "$SUCCESS_LIST_FILE"

echo "移动完成。"