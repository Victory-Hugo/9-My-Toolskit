#!/bin/bash

# 调试版本：快速诊断ascli下载问题
# 用于测试单个文件下载，排查延迟问题

OUTPUT_DIR="/mnt/d/迅雷下载/古代DNA/data/"
mkdir -p "$OUTPUT_DIR"

echo "=== ASCLI 下载调试工具 ==="
echo "时间: $(date)"
echo "输出目录: $OUTPUT_DIR"
echo

# 1. 检查ascli命令
echo "1. 检查ascli命令..."
if command -v ascli &> /dev/null; then
    echo "✓ ascli 命令可用"
    ascli --version
else
    echo "✗ ascli 命令未找到"
    exit 1
fi
echo

# 2. 检查配置
echo "2. 检查ascli配置..."
echo "ERA配置信息:"
ascli conf preset show era
echo

# 3. 测试服务器连接
echo "3. 测试服务器连接..."
echo "开始时间: $(date '+%H:%M:%S')"
if timeout 15 ascli -Pera server info; then
    echo "✓ 服务器连接成功"
else
    echo "✗ 服务器连接失败或超时"
fi
echo "结束时间: $(date '+%H:%M:%S')"
echo

# 4. 测试下载一个小文件
echo "4. 测试下载小文件..."
test_path="vol1/run/ERR953/ERR9539070/10337.bam.bai"
test_file="${OUTPUT_DIR}debug_test.bai"

echo "测试路径: $test_path"
echo "输出文件: $test_file"
echo "开始时间: $(date '+%H:%M:%S')"

# 删除可能存在的测试文件
rm -f "$test_file"

# 尝试下载，显示详细输出
echo "尝试方式1: 标准下载命令"
echo "执行命令: ascli -Pera server download \"$test_path\" --to-folder=\"$OUTPUT_DIR\""
timeout 60 ascli -Pera server download "$test_path" --to-folder="$OUTPUT_DIR"

echo
echo "尝试方式2: 带重命名的下载命令"
echo "执行命令: ascli server download -Pera \"$test_path\" --to-folder=\"$OUTPUT_DIR\" --name=\"debug_test.bai\""
timeout 60 ascli server download -Pera "$test_path" --to-folder="$OUTPUT_DIR" --name="debug_test.bai"

echo
echo "尝试方式3: 简化命令"
echo "执行命令: ascli server download -Pera \"$test_path\""
cd "$OUTPUT_DIR"
timeout 60 ascli server download -Pera "$test_path"
cd -

echo "结束时间: $(date '+%H:%M:%S')"

# 检查结果
if [[ -f "$test_file" && -s "$test_file" ]]; then
    file_size=$(stat -f%z "$test_file" 2>/dev/null || stat -c%s "$test_file" 2>/dev/null)
    echo "✓ 下载成功！文件大小: $file_size 字节"
    rm -f "$test_file"
else
    echo "✗ 下载失败或文件为空"
fi
echo

# 5. 网络连通性测试
echo "5. 网络连通性测试..."
echo "测试ping到 ftp.sra.ebi.ac.uk:"
ping -c 3 ftp.sra.ebi.ac.uk
echo

# 6. 显示系统信息
echo "6. 系统信息..."
echo "操作系统: $(uname -a)"
echo "当前用户: $(whoami)"
echo "当前目录: $(pwd)"
echo "磁盘空间:"
df -h "$OUTPUT_DIR"
echo

echo "=== 调试完成 ==="
echo "如果下载测试失败，可能的原因："
echo "1. 网络连接问题"
echo "2. ascli配置问题"
echo "3. 服务器端问题"
echo "4. 防火墙或代理问题"