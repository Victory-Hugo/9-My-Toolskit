#!/bin/bash

# 代码变换动画渲染脚本 - 自动渲染
# 直接运行: ./代码变换.sh

# ==================== 配置区域（直接写死的路径） ====================
SCRIPT_DIR="/mnt/c/Users/Administrator/Desktop"
CONDA_INIT="/home/luolintao/miniconda3/etc/profile.d/conda.sh"
ENV_NAME="Manim"
MANIM_SRC="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/2-视频音频/1-代码变换.py"
# 输入文件路径（写死）
OLD_CODE_FILE="$SCRIPT_DIR/old_code.py"
NEW_CODE_FILE="$SCRIPT_DIR/new_code.py"

# 输出文件名
OUTPUT_FILE="output.mp4"

# =====================================================================

echo "=================================================="
echo "代码变换动画渲染"
echo "=================================================="
echo "旧代码文件: $OLD_CODE_FILE"
echo "新代码文件: $NEW_CODE_FILE"
echo "输出文件: $SCRIPT_DIR/$OUTPUT_FILE"
echo "Conda 环境: $ENV_NAME"
echo "=================================================="
echo ""

# 验证输入文件是否存在
if [ ! -f "$OLD_CODE_FILE" ]; then
    echo "错误: 找不到文件 '$OLD_CODE_FILE'"
    exit 1
fi

if [ ! -f "$NEW_CODE_FILE" ]; then
    echo "错误: 找不到文件 '$NEW_CODE_FILE'"
    exit 1
fi

# 删除旧的视频目录（清理中间文件）
echo "清理旧的中间文件..."
rm -rf "$SCRIPT_DIR/videos"
rm -rf "$SCRIPT_DIR/images"
rm -rf "$SCRIPT_DIR/texts"

# 激活 Conda 环境并运行 Python 脚本
cd "$SCRIPT_DIR"
source "$CONDA_INIT"
conda activate "$ENV_NAME"

python3 "$MANIM_SRC" "$OLD_CODE_FILE" "$NEW_CODE_FILE" "$OUTPUT_FILE"

# 检查是否成功
if [ $? -eq 0 ]; then
    echo ""
    echo "=================================================="
    echo "✓ 渲染完成！"
    
    # 复制最终文件到桌面根目录
    if [ -f "$SCRIPT_DIR/videos/1440p60/$OUTPUT_FILE" ]; then
        cp "$SCRIPT_DIR/videos/1440p60/$OUTPUT_FILE" "$SCRIPT_DIR/$OUTPUT_FILE"
        echo "视频文件: $SCRIPT_DIR/$OUTPUT_FILE"
    fi
    
    echo "=================================================="
    echo ""
    echo "清理中间文件..."
    # 删除 Manim 生成的所有中间文件和目录
    rm -rf "$SCRIPT_DIR/videos"
    rm -rf "$SCRIPT_DIR/images"
    rm -rf "$SCRIPT_DIR/texts"
    echo "✓ 中间文件已删除"
    echo "=================================================="
else
    echo ""
    echo "=================================================="
    echo "✗ 渲染失败，请检查输入文件格式"
    echo "=================================================="
    exit 1
fi
