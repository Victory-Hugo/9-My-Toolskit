#!/bin/bash

# 脚本功能: 根据输入的分类单元名称获取完整基因组组装ID
# 用法: ./1.sh <taxon_name> [output_directory] [max_results]
# 示例: ./1.sh "Rickettsia prowazekii" /path/to/output 100

# 检查参数数量
if [ $# -lt 1 ]; then
    echo "用法: $0 <taxon_name> [output_directory] [max_results]"
    echo "示例: $0 \"Rickettsia prowazekii\" /path/to/output 100"
    echo "如果不指定输出目录，将使用当前目录"
    echo "如果不指定max_results，将获取所有完整基因组"
    echo "建议对于大型物种（如E.coli）设置较小的max_results值以提高速度"
    exit 1
fi

# 获取参数
TAXON_NAME="$1"
OUTPUT_DIR="${2:-.}"  # 如果未提供输出目录，使用当前目录
MAX_RESULTS="${3:-0}"  # 如果未提供最大结果数，默认为0（不限制）

# 检查必要工具
command -v datasets >/dev/null 2>&1 || {
    echo "错误: 未找到 datasets 工具，请确保已安装 NCBI Datasets CLI" >&2
    exit 1
}

command -v jq >/dev/null 2>&1 || {
    echo "错误: 未找到 jq 工具，请安装 jq" >&2
    exit 1
}

# 创建输出目录（如果不存在）
mkdir -p "$OUTPUT_DIR"

# 生成输出文件名（替换空格为下划线，移除特殊字符）
SAFE_NAME=$(echo "$TAXON_NAME" | tr ' ' '_' | sed 's/[^a-zA-Z0-9_-]//g')
OUTPUT_FILE="$OUTPUT_DIR/${SAFE_NAME}_complete_genomes.txt"
SUMMARY_FILE="$OUTPUT_DIR/${SAFE_NAME}_summary.txt"

echo "正在查询分类单元: $TAXON_NAME"
if [ "$MAX_RESULTS" -gt 0 ]; then
    echo "最大结果限制: $MAX_RESULTS"
fi
echo "输出文件: $OUTPUT_FILE"
echo "摘要文件: $SUMMARY_FILE"

# 获取完整基因组数据
echo "正在获取数据..."
echo "注意: 对于基因组数量较多的物种，此过程可能需要几分钟时间..."
TEMP_JSON=$(mktemp)
TEMP_ERROR=$(mktemp)

# 添加超时和错误处理的 datasets 查询
DATASETS_SUCCESS=false
if [ "$MAX_RESULTS" -gt 0 ]; then
    echo "限制结果数量: $MAX_RESULTS"
    echo "执行命令: datasets summary genome taxon \"$TAXON_NAME\" --limit $MAX_RESULTS"
    if timeout 300 datasets summary genome taxon "$TAXON_NAME" --limit "$MAX_RESULTS" > "$TEMP_JSON" 2>"$TEMP_ERROR"; then
        DATASETS_SUCCESS=true
    fi
else
    echo "执行命令: datasets summary genome taxon \"$TAXON_NAME\""
    if timeout 300 datasets summary genome taxon "$TAXON_NAME" > "$TEMP_JSON" 2>"$TEMP_ERROR"; then
        DATASETS_SUCCESS=true
    fi
fi

if [ "$DATASETS_SUCCESS" = false ]; then
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        echo "错误: 查询超时（5分钟），请检查网络连接或尝试更具体的分类单元名称" >&2
    else
        echo "错误: 无法获取 $TAXON_NAME 的数据" >&2
        echo "详细错误信息:" >&2
        cat "$TEMP_ERROR" >&2
    fi
    rm -f "$TEMP_JSON" "$TEMP_ERROR"
    exit 1
fi

# 清理错误文件
rm -f "$TEMP_ERROR"

# 检查是否有数据返回
TOTAL_COUNT=$(jq -r '.total_count // 0' "$TEMP_JSON")
if [ "$TOTAL_COUNT" -eq 0 ]; then
    echo "警告: 未找到 $TAXON_NAME 的任何基因组数据" >&2
    rm -f "$TEMP_JSON"
    exit 1
fi

echo "找到总计 $TOTAL_COUNT 个基因组"

# 提取完整基因组的组装ID
echo "正在提取完整基因组组装ID..."
jq -r '.reports[] | select(.assembly_info.assembly_level == "Complete Genome") | .accession' "$TEMP_JSON" > "$OUTPUT_FILE"

# 检查是否有完整基因组
COMPLETE_COUNT=$(wc -l < "$OUTPUT_FILE")
if [ "$COMPLETE_COUNT" -eq 0 ]; then
    echo "警告: 未找到 $TAXON_NAME 的完整基因组" >&2
    rm -f "$TEMP_JSON" "$OUTPUT_FILE"
    exit 1
fi

# 生成摘要信息
echo "正在生成摘要信息..."
{
    echo "=========================================="
    echo "基因组数据摘要 - $TAXON_NAME"
    echo "查询日期: $(date '+%Y-%m-%d %H:%M:%S')"
    if [ "$MAX_RESULTS" -gt 0 ]; then
        echo "结果限制: $MAX_RESULTS (注意: 这可能不包含所有可用基因组)"
    fi
    echo "=========================================="
    echo ""
    echo "总基因组数量: $TOTAL_COUNT"
    echo "完整基因组数量: $COMPLETE_COUNT"
    echo ""
    echo "完整基因组菌株信息:"
    echo "------------------------------------------"
    jq -r '.reports[] | select(.assembly_info.assembly_level == "Complete Genome") | [.accession, .organism.organism_name] | @tsv' "$TEMP_JSON" | \
    sort | \
    awk -F'\t' '{printf "%-20s %s\n", $1, $2}'
    echo ""
    echo "独特菌株列表:"
    echo "------------------------------------------"
    jq -r '.reports[] | select(.assembly_info.assembly_level == "Complete Genome") | .organism.organism_name' "$TEMP_JSON" | \
    sort -u | \
    nl -w2 -s'. '
    echo ""
    echo "文件输出位置:"
    echo "- 组装ID列表: $OUTPUT_FILE"
    echo "- 摘要信息: $SUMMARY_FILE"
    echo "=========================================="
} > "$SUMMARY_FILE"

# 清理临时文件
rm -f "$TEMP_JSON"

# 显示结果
echo ""
echo "✓ 成功完成!"
echo "✓ 找到 $COMPLETE_COUNT 个完整基因组"
echo "✓ 组装ID已保存到: $OUTPUT_FILE"
echo "✓ 详细摘要已保存到: $SUMMARY_FILE"
echo ""

# 显示前几个结果作为预览
echo "前10个组装ID预览:"
head -10 "$OUTPUT_FILE" | nl -w2 -s'. '

if [ "$COMPLETE_COUNT" -gt 10 ]; then
    echo "... 还有 $((COMPLETE_COUNT - 10)) 个组装ID，请查看完整文件"
fi

echo ""
echo "使用以下命令查看完整结果:"
echo "cat $OUTPUT_FILE"
echo "cat $SUMMARY_FILE"
