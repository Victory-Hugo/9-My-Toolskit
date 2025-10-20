#!/bin/bash
#* 此脚本用于通过 Aspera ascp 工具从 CNCB 下载指定的 HRA 数据集。
#* 变量说明：
#*   ASCP_PATH: ascp 工具的路径
#*   SECRET_FILE: Aspera 认证密钥文件路径
#*   HRA_NAME: 需要下载的数据集名称
#*   SAVE_PATH: 数据保存的本地路径
#* 步骤说明：
#*   1. 创建保存数据的本地目录。
#*   2. 使用 ascp 工具通过指定端口和密钥文件从 CNCB 下载数据集到本地目录。

ASCP_PATH="/home/luolintao/miniconda3/envs/pyg/bin/ascp"
SECRET_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/3-CNCB/conf/aspera01.openssh"
HRA_NAME="HRA000283"
CRA_NAME="CRA000283"
SAVE_PATH="/mnt/g/2-MBE-Tubo/data/"
LOG_DIR="${SAVE_PATH}/log/"

mkdir -p "$SAVE_PATH"
mkdir -p "$LOG_DIR"

# "${ASCP_PATH}" \
#     -P33001 \
#     -i "$SECRET_FILE" \
#     -QT \
#     -l100m \
#     -L ${LOG_DIR} \
#     -k1 \
#     -d "aspera01@download.cncb.ac.cn:gsa-human/${HRA_NAME}" \
#     "$SAVE_PATH"

"${ASCP_PATH}" \
    -P33001 \
    -i "$SECRET_FILE" \
    -QT \
    -l100m \
    -L ${LOG_DIR} \
    -k1 \
    -d "aspera01@download.cncb.ac.cn:gsa/${CRA_NAME}" \
    "$SAVE_PATH"

#* 参数说明：
#*   -P33001: 指定端口号为 33001
#*  -i: 指定密钥文件
#*   -QT: 启用静默模式和禁用加密
#*   -l100m: 限制传输速率为 100MB/s
#*  -k1: 断点续传
#*   -d: 指定远程下载路径

