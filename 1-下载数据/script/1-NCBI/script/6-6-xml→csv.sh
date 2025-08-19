: '
脚本功能说明：
本脚本用于批量处理 XML 文件并将其转换为 CSV 格式，最后合并所有生成的 CSV 文件。

步骤说明：
1. 设置相关变量，包括 Python 解释器路径、Python 脚本路径、输入 XML 文件夹、输出 CSV 文件夹及最终合并的 CSV 文件路径。
2. 确保输出目录存在，如果不存在则自动创建。
3. 使用 GNU parallel 工具并行处理所有 XML 文件，调用指定的 Python 脚本将每个 XML 文件转换为 CSV 文件，输出到指定目录。
4. 调用另一个 Python 脚本，将所有生成的 CSV 文件合并为一个最终的 CSV 文件。

依赖说明：
- 需要安装 GNU parallel 工具。
- 需要 Python3 及相关 Python 脚本。
'
#!/bin/bash

PYTHON3="python3"
PY_SCRIPT1="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/python/6-6-xml→csv.py"
PY_SCRIPT2="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/python/6-7-csv-concat.py"
XML_DIR="/mnt/d/迅雷下载/鲍曼组装/xml"
OUT_DIR="/mnt/d/迅雷下载/鲍曼组装/csv"
FINAL_CSV="/mnt/d/迅雷下载/鲍曼组装/merged.csv"

# 确保输出目录存在
mkdir -p "$OUT_DIR"

# 用 GNU parallel 并行处理
find "$XML_DIR" -name "*.xml" | parallel --bar -j 10 \
    "$PYTHON3" "$PY_SCRIPT1" {} "$OUT_DIR/"

"$PYTHON3" "$PY_SCRIPT2" \
    "$OUT_DIR" "$FINAL_CSV"