: '
脚本功能说明：
本脚本用于根据指定的BioProject编号，自动获取其相关的SRA（Sequence Read Archive）运行信息，并以CSV格式输出到指定文件。
主要步骤包括：
1. 使用NCBI的esearch工具在bioproject数据库中查询目标BioProject编号。
2. 通过elink工具将BioProject与对应的SRA条目关联。
3. 利用efetch工具以runinfo格式获取详细的SRA运行信息，并保存为CSV文件。

使用前提：
- 需提前安装NCBI命令行工具（如esearch、elink、efetch）。
- 请根据实际需求修改PROJECT_NUMBER和OUT_CSV变量。

注意事项：
- 具体安装NCBI工具包的方法请参考相关文档（../markdown/1-NCBI工具包安装.md）。
- 输出文件路径需确保有写入权限。
'
#!/bin/bash

# 如下脚本的功能是将BioProject的基础信息获得
# 首先需要确保安装了NCBI的工具包
# 具体安装方法请参考../markdown/1-NCBI工具包安装.md


PROJECT_NUMBER="PRJNA778930"  # 替换为你需要的BioProject编号
OUT_CSV="/mnt/c/Users/Administrator/Desktop/PRJNA778930_runinfo.csv" # 替换为输出文件路径

#TODO 再次提醒，需要安装NCBI的工具包

esearch -db bioproject -query ${PROJECT_NUMBER} \
  | elink -target sra \
  | efetch -format runinfo > ${OUT_CSV}
