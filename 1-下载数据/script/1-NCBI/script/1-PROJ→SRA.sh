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
