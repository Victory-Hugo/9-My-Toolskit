: '
脚本功能说明：
本脚本用于根据指定的 NCBI BioProject 编号（如 PRJNA572371），
自动检索并下载相关的 SRA 运行信息或 Assembly 信息，并保存为 CSV 文件。
#! 注意，本脚本无法一次性获得project中所有样本的最详细的基础信息。
#! 注意，本脚本无法一次性获得project中所有样本的最详细的基础信息。
#! 注意，本脚本主要用于获取项目下的测序编号。
主要流程：
1. 解除代理设置，确保网络请求不受代理影响。
2. 首先尝试通过 esearch/elink/efetch 获取 SRA runinfo 信息，保存为 CSV 文件。
3. 若未获取到有效 SRA 信息，则自动切换到 Assembly 数据下载模式：
  - 通过 esearch/efetch/xtract 获取 Assembly 相关信息（包括 BioSample、组装、物种、FTP 路径等），并格式化输出为表格。
  - 仅保留前 13 列数据，并添加表头，最终保存为 CSV 文件。
4. 输出处理进度和结果日志。

依赖工具：
- NCBI Entrez Direct 工具集（esearch、elink、efetch、xtract）
- bash shell

参数说明：
- PROJECT_NUMBER：指定的 BioProject 编号
- OUT_CSV：输出的 CSV 文件路径

适用场景：
- 批量下载和整理 NCBI BioProject 下的 SRA 或 Assembly 数据信息
- 数据分析前的自动化信息收集

作者：自定义
'
#!/bin/bash
set -euo pipefail
unset http_proxy
unset https_proxy

PROJECT_NUMBER="PRJNA572371"
OUT_CSV="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/conf/${PROJECT_NUMBER}_runinfo.csv"

echo "[$(date +'%F %T')] 开始处理 BioProject ${PROJECT_NUMBER}"

# Step 1: 尝试获取 SRA runinfo
echo "[$(date +'%F %T')] 尝试获取 SRA 运行信息..."
esearch -db bioproject -query "${PROJECT_NUMBER}" \
  | elink -target sra \
  | efetch -format runinfo \
  > "${OUT_CSV}" || true

if [ ! -s "${OUT_CSV}" ] || [ "$(wc -l < "${OUT_CSV}")" -le 1 ]; then
  echo "[$(date +'%F %T')] 未检索到有效的 SRA 运行信息 (行数: $(wc -l < "${OUT_CSV}"))"
  echo "[$(date +'%F %T')] 切换到 Assembly 数据下载模式..."

  # 先获取原始数据，然后手动处理列对齐
  temp_file=$(mktemp)
  
  esearch -db assembly -query "${PROJECT_NUMBER}" \
    | efetch -format docsum \
    | xtract \
        -pattern DocumentSummary \
          -element BioSampleAccn AssemblyAccession SubmitterOrganization AssemblyName AssemblyStatus SeqReleaseDate SpeciesName Taxid \
        -block Synonym \
          -element Genbank \
        -block FtpPath_RefSeq \
          -element FtpPath_RefSeq \
        -block FtpPath_GenBank \
          -element FtpPath_GenBank \
        -block Stat \
          -match "@category:total_length" \
          -element Stat \
        -block Stat \
          -match "@category:contig_count" \
          -element Stat \
        -block Stat \
          -match "@category:scaffold_count" \
          -element Stat \
    > "$temp_file"

  # 创建表头和处理数据
  {
    echo -e "BioSampleAccn\tAssemblyAccession\tSubmitter\tAssemblyName\tAssemblyStatus\tSeqReleaseDate\tSpeciesName\tTaxid\tGenbankAccession\tRefSeqFtp\tGenBankFtp\tTotalLength\tContigCount\tScaffoldCount"

    # 处理数据行，只保留前13列
    while IFS=$'\t' read -r col1 col2 col3 col4 col5 col6 col7 col8 col9 col10 col11 col12 col13 rest; do
      echo -e "${col1}\t${col2}\t${col3}\t${col4}\t${col5}\t${col6}\t${col7}\t${col8}\t${col9}\t${col10}\t${col11}\t${col12}\t${col13}"
    done < "$temp_file"
  } > "${OUT_CSV}"
  
  rm -f "$temp_file"

  echo "[$(date +'%F %T')] Assembly 信息已保存到 ${OUT_CSV}"
else
  echo "[$(date +'%F %T')] 成功获取 SRA 运行信息，已保存到 ${OUT_CSV} (行数: $(wc -l < "${OUT_CSV}"))"
fi

echo "[$(date +'%F %T')] 脚本执行完毕"
