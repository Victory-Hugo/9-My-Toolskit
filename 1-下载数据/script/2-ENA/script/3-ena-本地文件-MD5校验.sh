#!/usr/bin/env bash
# 开启严格模式：一旦出错即退出；未定义变量报错；管道中任意一段失败即报错
set -euo pipefail

# 下载目录（请根据实际情况修改）
DOWNLOAD_DIR="/mnt/d/迅雷下载/ENA/finished_3"
# MD5 结果记录文件
MD5_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf/md5.txt"

# 如果 MD5_FILE 不存在，则创建之
touch "$MD5_FILE"

# 扫描所有 *.fastq.gz 文件，一次性读入数组（支持文件名中含空格）
mapfile -d '' files < <(find "$DOWNLOAD_DIR" -type f -name "*fastq.gz" -print0)

# 将已计算过的文件加载到一个 Bash 关联数组中
declare -A done
while read -r checksum filepath; do
  # filepath 可能含有空格；此处 checksum 为第一列，filepath 为第二列
  done["$filepath"]=1
done < "$MD5_FILE"

# 捕获中断信号，优雅退出
trap 'echo "脚本被中断，已保存当前进度。"; exit 1' SIGINT SIGTERM

# 遍历所有待处理文件
for file in "${files[@]}"; do
  # 跳过已记录的文件
  if [[ -n "${done[$file]:-}" ]]; then
    echo "跳过：$file"
    continue
  fi

  # 计算 MD5 并追加到记录文件
  md5sum "$file" >> "$MD5_FILE"
  echo "已记录：$file"
done

echo "全部完成！"
