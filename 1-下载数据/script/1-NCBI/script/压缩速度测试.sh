#!/usr/bin/env bash
# 压缩速度测试脚本

set -euo pipefail

# 测试文件路径
TEST_FILE="/home/luolintao/10_鲍曼/PRJNA1225594/SRR32394746/SRR32394746_1.fastq"

if [[ ! -f "${TEST_FILE}" ]]; then
    echo "测试文件不存在: ${TEST_FILE}"
    exit 1
fi

echo "=== 压缩速度测试 ==="
echo "测试文件: ${TEST_FILE}"
echo "文件大小: $(du -h "${TEST_FILE}" | cut -f1)"
echo

# 创建临时目录
TEMP_DIR="/tmp/compress_test_$$"
mkdir -p "${TEMP_DIR}"

# 复制测试文件
cp "${TEST_FILE}" "${TEMP_DIR}/test.fastq"

cd "${TEMP_DIR}"

echo "1. 标准 gzip 压缩测试..."
time gzip -1 -c test.fastq > test_gzip1.gz
echo "压缩后大小: $(du -h test_gzip1.gz | cut -f1)"
echo

echo "2. pigz 快速压缩测试 (8线程)..."
cp "${TEST_FILE}" test2.fastq
time pigz -p 8 -1 test2.fastq
echo "压缩后大小: $(du -h test2.fastq.gz | cut -f1)"
echo

echo "3. pigz 快速压缩测试 (32线程)..."
cp "${TEST_FILE}" test3.fastq
time pigz -p 32 -1 test3.fastq
echo "压缩后大小: $(du -h test3.fastq.gz | cut -f1)"
echo

echo "4. 不压缩 (仅复制)..."
time cp "${TEST_FILE}" test_no_compress.fastq
echo "文件大小: $(du -h test_no_compress.fastq | cut -f1)"
echo

# 清理
cd /
rm -rf "${TEMP_DIR}"

echo "=== 测试完成 ==="
