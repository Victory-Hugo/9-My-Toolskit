#!/bin/bash
# 测试树状结构功能的小脚本

TEST_DIR="/tmp/test_tree_structure_$$"
mkdir -p "$TEST_DIR"

echo "创建测试目录结构..."
# 创建12000个测试目录来模拟大量文件的情况
for i in {1..12000}; do
    mkdir -p "$TEST_DIR/test_dir_$(printf "%05d" $i)"
done

echo "测试目录创建完成: $TEST_DIR"
echo "目录数量: $(find "$TEST_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)"

# 运行我们的树状整理脚本
echo "运行树状整理脚本..."
"/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/1-NCBI/pipe/2-解压整理.sh" "$TEST_DIR" --max-files 5000

echo ""
echo "整理后的结构："
echo "一级目录数: $(find "$TEST_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)"
echo "二级目录数: $(find "$TEST_DIR" -mindepth 2 -maxdepth 2 -type d | wc -l)"
echo "三级目录数: $(find "$TEST_DIR" -mindepth 3 -maxdepth 3 -type d | wc -l)"

echo ""
echo "示例目录结构："
ls "$TEST_DIR" | head -5

echo ""
echo "清理测试目录..."
rm -rf "$TEST_DIR"*
echo "测试完成！"