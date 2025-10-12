#!/bin/bash
# ENA BAM文件链接拆分脚本使用示例
BASE_DIR="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA" #* 脚本所在目录

# 设置输入文件路径
INPUT_TSV="$BASE_DIR/conf/PRJEB25445.tsv" #* 这个文件来自0-0-project→全部信息.sh
OUTPUT_DIR="$BASE_DIR/conf" #* 输出目录路径（可选，如果不指定则使用输入文件所在目录）
SCRIPT_PATH="$BASE_DIR/python/2-ENA-BAM-链接拆分.py" #* Python脚本路径

echo "=== ENA BAM文件链接拆分工具 ==="
echo "输入文件: $INPUT_TSV"
echo "输出目录: $OUTPUT_DIR"
echo "================================"

# 检查输入文件是否存在
if [ ! -f "$INPUT_TSV" ]; then
    echo "错误：输入文件不存在: $INPUT_TSV"
    exit 1
fi

# 运行Python脚本
# 方式1：指定输出目录
python3 "$SCRIPT_PATH" "$INPUT_TSV" "$OUTPUT_DIR"

# 方式2：使用默认输出目录（与输入文件同目录）
# python3 "$SCRIPT_PATH" "$INPUT_TSV"

echo "脚本执行完成！"
