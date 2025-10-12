#!/usr/bin/env bash
set -euo pipefail

#*######################################
#* 脚本功能：生成下载列表文件
#* 从指定目录的 *.url 文件中提取下载链接
#* 生成统一的下载列表文件
#*######################################

URL_DIR="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf" #? 存放 *.url 文件的目录
OUT_LIST="/mnt/d/迅雷下载/古代DNA/补充下载/conf/download.txt" #? 每行一个下载路径:vol1/run/ERR953/ERR9539070/10337.bam

# 彩色打印函数
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

print_success() {
    echo -e "\033[32m[SUCCESS]\033[0m $1"
}

# 检查URL目录是否存在
if [[ ! -d "$URL_DIR" ]]; then
    print_error "URL目录不存在: $URL_DIR"
    exit 1
fi

# 确保输出目录存在
mkdir -p "$(dirname "$OUT_LIST")"

print_info "开始生成下载列表..."
print_info "URL文件目录: $URL_DIR"
print_info "输出列表文件: $OUT_LIST"

# 清空或创建输出文件
: > "$OUT_LIST"

# 统计处理的文件数
url_file_count=0
total_urls=0

# 构造 download 列表
find "$URL_DIR" -type f -name "*.url" | while IFS= read -r url_file; do
    [ -r "$url_file" ] || continue
    ((url_file_count++))
    print_info "处理URL文件 [$url_file_count]: $(basename "$url_file")"
    
    # 统计当前文件的URL数量
    current_file_urls=0
    grep -vE '^\s*#' "$url_file" | grep -vE '^\s*$' |
    while IFS= read -r line; do
        echo "$line"
        ((current_file_urls++))
    done
    
    print_info "  └─ 提取URL数量: $current_file_urls"
    ((total_urls += current_file_urls))
done | sort -u >> "$OUT_LIST"

# 检查生成的列表是否为空
if [ ! -s "$OUT_LIST" ]; then
    print_error "生成的下载列表为空: $OUT_LIST"
    print_error "请检查URL目录中是否存在有效的 *.url 文件"
    exit 1
fi

# 统计最终结果
final_count=$(wc -l < "$OUT_LIST")
print_success "下载列表生成完成！"
print_info "处理的URL文件数量: $url_file_count"
print_info "去重后的下载链接数量: $final_count"
print_info "下载列表保存位置: $OUT_LIST"

# 显示前几行作为预览
print_info "下载列表预览（前5行）:"
head -5 "$OUT_LIST" | while IFS= read -r line; do
    echo "  - $line"
done

if [[ $final_count -gt 5 ]]; then
    echo "  ... 还有 $((final_count - 5)) 个文件"
fi