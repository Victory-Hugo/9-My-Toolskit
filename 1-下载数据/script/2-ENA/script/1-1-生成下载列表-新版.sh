#!/usr/bin/env bash

#*######################################
#* 脚本功能：生成下载列表文件
#* 从指定目录的 *.url 文件中提取下载链接
#* 生成统一的下载列表文件
#*######################################

# 配置变量
URL_DIR="/mnt/d/迅雷下载/古代DNA/BAM/conf/"
OUT_LIST="/mnt/d/迅雷下载/古代DNA/BAM/conf/download.txt"

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
> "$OUT_LIST"

# 统计变量
url_file_count=0
total_urls=0

# 创建临时文件存储所有URL
temp_file=$(mktemp)

# 清理函数
cleanup() {
    rm -f "$temp_file"
}
trap cleanup EXIT

# 处理每个.url文件
for url_file in "$URL_DIR"*.url; do
    # 检查文件是否存在（glob可能没有匹配）
    if [[ ! -f "$url_file" ]]; then
        continue
    fi
    
    # 检查文件是否可读且不为空
    if [[ ! -r "$url_file" ]]; then
        print_warn "文件不可读: $(basename "$url_file")"
        continue
    fi
    
    if [[ ! -s "$url_file" ]]; then
        print_warn "跳过空文件: $(basename "$url_file")"
        continue
    fi
    
    url_file_count=$((url_file_count + 1))
    print_info "处理URL文件 [$url_file_count]: $(basename "$url_file")"
    
    # 统计当前文件的URL数量
    current_file_urls=0
    
    # 读取文件内容
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 去除行首尾空白字符
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 跳过空行和注释行
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            echo "$line" >> "$temp_file"
            current_file_urls=$((current_file_urls + 1))
        fi
    done < "$url_file"
    
    print_info "  └─ 提取URL数量: $current_file_urls"
    total_urls=$((total_urls + current_file_urls))
done

# 去重并写入最终文件
if [[ -s "$temp_file" ]]; then
    sort -u "$temp_file" > "$OUT_LIST"
else
    print_error "没有找到任何有效的URL"
    exit 1
fi

# 检查生成的列表是否为空
if [[ ! -s "$OUT_LIST" ]]; then
    print_error "生成的下载列表为空: $OUT_LIST"
    print_error "请检查URL目录中是否存在有效的 *.url 文件"
    exit 1
fi

# 统计最终结果
final_count=$(wc -l < "$OUT_LIST")
print_success "下载列表生成完成！"
print_info "处理的URL文件数量: $url_file_count"
print_info "去重前的URL总数: $total_urls"
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