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
