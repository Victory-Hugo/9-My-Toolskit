#!/bin/bash
# 一键运行批处理脚本（支持 screen / tmux）

# 配置
SESSION_NAME="SRA→FQ_run"
SCRIPT_PATH="/home/luolintao/0_Github/9-My-Toolskit/1-下载数据/script/1-NCBI/script/5-sra→fastq-simple-revised.sh"
LOG_FILE="SRA→FQ_run.log"

echo "🧬 启动 $SESSION_NAME 批处理..."
echo "会话名称: $SESSION_NAME"
echo "日志文件: $LOG_FILE"
echo "目标脚本: $SCRIPT_PATH"
echo "================================="

# 优先使用 screen
if command -v tmux &>/dev/null; then
    echo "✅ 检测到tmux"
    tmux new-session -d -s "$SESSION_NAME" "bash \"$SCRIPT_PATH\" > \"$LOG_FILE\" 2>&1"
    echo "运行命令: tmux attach -t $SESSION_NAME"
    echo "挂起会话: Ctrl+B D"

elif command -v screen &>/dev/null; then
    echo "✅ 检测到 screen，使用 screen 运行"
    screen -dmS "$SESSION_NAME" bash -c "bash \"$SCRIPT_PATH\" > \"$LOG_FILE\" 2>&1"
    echo "运行命令: screen -r $SESSION_NAME"
    echo "挂起会话: Ctrl+A D"
else
    echo "❌ 既没有 screen 也没有 tmux，请先安装其中一个"
    exit 1
fi

echo "🎉 脚本已提交后台运行"