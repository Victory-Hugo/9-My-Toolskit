#!/bin/bash
#*##############################################
#*============组装编号→数据下载==================
#*============组装编号→样本编号→基础信息下载======
#*#############################################

unset http_proxy
unset https_proxy
#*============组装编号→数据下载==================

PYTHON_SCRIPT="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/1-NCBI/python/7-下载NCBI的Assembly.py"
TXT_FILE="/mnt/d/5-NCBI-Reference/1-Bac/conf/补充下载.txt"
PYTHON_PATH="python3"
DOWNLOAD_PATH="/mnt/d/5-NCBI-Reference/1-Bac/download2"
mkdir -p "${DOWNLOAD_PATH}"

${PYTHON_PATH} \
  ${PYTHON_SCRIPT} \
  --base-path "${DOWNLOAD_PATH}" \
  --file-path "${TXT_FILE}" \
  -w 10 --resume


#*============组装编号→样本编号→基础信息下载======
echo "现在开始下载样本基本信息………………………………"

# 调用BioSample信息获取脚本
BIOSAMPLE_SCRIPT="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/1-NCBI/script/7-2-GCA_GCF→SAMN+xml.sh"

# 设置输出目录为与下载目录同级的meta文件夹
META_DIR="$(dirname "${DOWNLOAD_PATH}")/meta"

# 执行BioSample信息获取
"${BIOSAMPLE_SCRIPT}" \
  --input-file "${TXT_FILE}" \
  --output-dir "${META_DIR}" \
  --parallel 5

echo "组装数据下载和样本信息获取完成！"
echo "下载数据位置: ${DOWNLOAD_PATH}"
echo "样本信息位置: ${META_DIR}"

#*============自动解压和整理下载的数据==================
echo "现在开始解压和整理下载的数据………………………………"

# 调用Python解压整理模块
EXTRACT_SCRIPT="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/1-NCBI/python/extract_and_organize.py"

# 执行解压整理
python3 "${EXTRACT_SCRIPT}" "${DOWNLOAD_PATH}" --verbose

echo "所有处理步骤完成！"
echo "下载数据位置: ${DOWNLOAD_PATH}"
echo "样本信息位置: ${META_DIR}"
