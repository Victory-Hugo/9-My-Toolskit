#!/bin/bash

#* ==============================================
#* 第一步：调用SAMN→XML下载
#* ==============================================
BASE_DIR="/mnt/l/tmp/You_MG_2022/"
INPUT_FILE="${BASE_DIR}/conf/SAMN.txt"                                                   # 输入文件路径（包含SAMN编号的文件）
BIOSAMPLE_DIR="${BASE_DIR}/meta/xml"                                                     # 输出目录（Biosample XML文件保存位置）
LOG_FILE="${BASE_DIR}/log/download_log.txt"                                              # 日志文件路径
PARALLEL_JOBS=6                                                                          # 并行任务数（建议1-20之间，根据NCBI API限制调整）  
SCRIPT_PATH="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/1-NCBI/script/7-3-SAMN→xml→SRA→xml.sh"   # 实际执行脚本的路径

# ==============================================
# 参数验证和环境检查
# ==============================================

echo "======================================"
echo "样本信息获取管道启动"
echo "======================================"

# 创建必要的目录结构
echo "创建必要的目录结构..."
mkdir -p "$(dirname "$INPUT_FILE")"        # 创建conf目录
mkdir -p "$BIOSAMPLE_DIR"                  # 创建XML输出目录
mkdir -p "$(dirname "$LOG_FILE")"          # 创建log目录
echo "目录结构创建完成"
echo ""

# 检查输入文件
if [ ! -f "$INPUT_FILE" ]; then
    echo "错误：输入文件不存在: $INPUT_FILE"
    echo "请检查输入文件路径或创建包含SAMN编号的文件"
    exit 1
fi

# 检查执行脚本
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "错误：执行脚本不存在: $SCRIPT_PATH"
    echo "请检查脚本路径是否正确"
    exit 1
fi

# 检查输入文件是否为空
if [ ! -s "$INPUT_FILE" ]; then
    echo "警告：输入文件为空: $INPUT_FILE"
    echo "请确认文件中包含有效的SAMN编号"
    exit 1
fi

# 验证并行任务数
if ! [[ "$PARALLEL_JOBS" =~ ^[0-9]+$ ]] || [ "$PARALLEL_JOBS" -lt 1 ] || [ "$PARALLEL_JOBS" -gt 20 ]; then
    echo "错误：并行任务数必须是1-20之间的整数"
    echo "当前设置: $PARALLEL_JOBS"
    exit 1
fi

# 显示配置信息
echo "配置信息："
echo "- 输入文件: $INPUT_FILE"
echo "- 输出目录: $BIOSAMPLE_DIR"  
echo "- 日志文件: $LOG_FILE"
echo "- 并行任务数: $PARALLEL_JOBS"
echo "- 执行脚本: $SCRIPT_PATH"
echo ""

# 统计输入样本数量
sample_count=$(grep -v '^[[:space:]]*$' "$INPUT_FILE" | wc -l)
echo "输入文件中有效样本数量: $sample_count"



# 调用实际的下载脚本，传递所有参数
bash "$SCRIPT_PATH" "$INPUT_FILE" "$BIOSAMPLE_DIR" "$LOG_FILE" "$PARALLEL_JOBS"


#* ==============================================
#* 第二步：调用XML→CSV
#* ==============================================
PYTHON3="python3"
SCR_DIR="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/1-NCBI/python/"
PY_SCRIPT1="${SCR_DIR}6-6-xml→csv_Biosample.py"
PY_SCRIPT1_2="${SCR_DIR}6-6-xml→csv_SRA.py"
PY_SCRIPT2="${SCR_DIR}6-7-csv-concat.py"
META_DIR="/mnt/l/tmp/You_MG_2022/meta/"
XML_DIR="${META_DIR}/xml"
CSV_DIR="${META_DIR}/csv"
FINAL_CSV="${META_DIR}/merged.csv"

# 确保输出目录存在
mkdir -p "$CSV_DIR"

# 用 GNU parallel 并行处理
find "$XML_DIR" -name "*.xml" | parallel --bar -j 10 \
    "$PYTHON3" "$PY_SCRIPT1" {} "$CSV_DIR/"

"$PYTHON3" "$PY_SCRIPT2" \
    "$CSV_DIR" "$FINAL_CSV"

echo "XML转换为CSV完成，合并文件保存为: $FINAL_CSV"
echo "删除中间CSV文件..."
rm -rf "${CSV_DIR}"

echo "压缩所有xml文件..."
if [ -d "$XML_DIR" ] && [ "$(ls -A "$XML_DIR" 2>/dev/null | wc -l)" -gt 0 ]; then
    tar -czvf "${META_DIR}/xml_files.tar.gz" -C "$XML_DIR" .
    if [ $? -eq 0 ]; then
        echo "XML文件压缩成功，删除原始XML文件..."
        rm -rf "$XML_DIR"
        echo "XML文件已删除，保留压缩文件: ${META_DIR}/xml_files.tar.gz"
    else
        echo "警告：XML文件压缩失败，保留原始文件"
    fi
else
    echo "警告：XML目录不存在或为空，跳过压缩"
fi
echo "处理完成！"