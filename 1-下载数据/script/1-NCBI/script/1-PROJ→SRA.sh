: '
脚本功能说明：
本脚本用于根据指定的 NCBI BioProject 编号（如 PRJNA1219970），自动检索并下载相关的 SRA 运行信息或 Assembly 信息，并将结果保存为 CSV 文件。

主要流程：
1. 通过 esearch/elink/efetch 工具链尝试获取 BioProject 对应的 SRA RunInfo 信息，并保存为 CSV 文件。
2. 若未检索到有效的 SRA 运行信息（文件不存在或仅有表头），则自动切换到 Assembly 数据下载模式，获取并保存 Assembly 相关信息。
3. 所有操作均有详细的时间戳日志输出，便于追踪处理进度。

参数说明：
- PROJECT_NUMBER：需查询的 BioProject 编号（可根据实际需求修改）。
- OUT_CSV：输出结果 CSV 文件的路径，默认保存到桌面并以 BioProject 编号命名。

依赖工具：
- NCBI Entrez Direct 工具集（esearch, elink, efetch, xtract）
- bash shell

使用方法：
1. 修改 PROJECT_NUMBER 为目标 BioProject 编号。
2. 运行脚本，结果将自动保存到指定路径。

适用场景：
- 批量下载 NCBI SRA 或 Assembly 元数据
- 自动化生信数据整理流程
'

#!/bin/bash
set -euo pipefail
# PRJNA1112767
# PRJNA1225594
# PRJNA1219970
# PRJNA1028672
# PRJNA572371
PROJECT_NUMBER="PRJNA572371"   # 替换为你的 BioProject 编号
OUT_CSV="/mnt/c/Users/Administrator/Desktop/${PROJECT_NUMBER}_runinfo.csv" 

echo "[$(date +'%F %T')] 开始处理 BioProject ${PROJECT_NUMBER}"

#### 第一步：尝试获取 SRA RunInfo ####
echo "[$(date +'%F %T')] 尝试获取 SRA 运行信息..."
esearch -db bioproject -query "${PROJECT_NUMBER}" \
  | elink -target sra \
  | efetch -format runinfo \
  > "${OUT_CSV}" || true

# 如果文件不存在或只有表头（即行数 ≤1），则认为无 SRA 数据
if [ ! -s "${OUT_CSV}" ] || [ "$(wc -l < "${OUT_CSV}")" -le 1 ]; then
  echo "[$(date +'%F %T')] 未检索到有效的 SRA 运行信息 (行数: $(wc -l < "${OUT_CSV}"))"
  echo "[$(date +'%F %T')] 切换到 Assembly 数据下载模式..."

  #### 第二步：获取 Assembly 信息 ####
  esearch -db assembly -query "${PROJECT_NUMBER}" \
    | efetch -format docsum \
    | xtract \
        -pattern DocumentSummary \
          -element \
            AssemblyAccession AssemblyName AssemblyStatus SeqReleaseDate SpeciesName Taxid BioProject BioSample Submitter \
        -block Synonym \
          -element Synonym \
        -block FtpPath_RefSeq \
          -element FtpPath_RefSeq \
        -block FtpPath_GenBank \
          -element FtpPath_GenBank \
        -block Statistics \
          -element Stats_AssemblySize Stats_ContigCount Stats_ScaffoldCount \
    > "${OUT_CSV}"

  echo "[$(date +'%F %T')] Assembly 信息已保存到 ${OUT_CSV}"
else
  echo "[$(date +'%F %T')] 成功获取 SRA 运行信息，已保存到 ${OUT_CSV} (行数: $(wc -l < "${OUT_CSV}"))"
fi

echo "[$(date +'%F %T')] 脚本执行完毕"
