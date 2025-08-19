: '
脚本功能：
    本脚本用于下载 NCBI 的组装（Assembly）数据。
    通过调用指定的 Python 脚本，并传递配置文件和下载路径参数，实现自动化下载。

参数说明：
    PYTHON_SCRIPT  - 指定用于下载的 Python 脚本路径。
    TXT_FILE       - 包含下载信息的配置文件路径。
    PYTHON_PATH    - Python 解释器路径（建议使用虚拟环境）。
    DOWNLOAD_PATH  - 数据下载保存的目标路径。

使用说明：
    运行本脚本前，请确保上述路径均已正确设置，且所需 Python 环境及依赖已安装。
    执行脚本后，将自动根据配置文件内容下载 NCBI 组装数据至指定目录。
'
#! /bin/bash
set -euo pipefail
unset http_proxy
unset https_proxy
#* 下载 NCBI 数据的组装数据
PYTHON_SCRIPT="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/python/7-下载NCBI的Assembly.py"
TXT_FILE="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/conf/鲍曼NC2025组装.txt"
PYTHON_PATH="/home/luolintao/miniconda3/envs/pyg/bin/python3"
DOWNLOAD_PATH="/mnt/d/迅雷下载/鲍曼组装2"
mkdir -p "${DOWNLOAD_PATH}"
# 然后：
${PYTHON_PATH} \
  ${PYTHON_SCRIPT} \
  --base-path "${DOWNLOAD_PATH}" \
  --file-path "${TXT_FILE}"

#!不推荐下列方式，因为潜在的被墙风险
# datasets \
#     download genome \
#     accession GCF_040009695.1 \
#     --filename GCF_040009695.1.zip \
#     --include genome

# datasets \
#     download genome \
#     accession GCF_040009695.1 \
#     --filename GCF_040009695.1.zip \
#     --include gff3,rna,cds,protein,genome,seq-report