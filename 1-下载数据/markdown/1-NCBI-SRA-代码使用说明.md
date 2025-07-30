# 说明
如下文本介绍了如何使用`1-下载数据/script/1-NCBI/6-NCBI-SRA-download.sh`进行下载。
# 网站
[BioSample Links for BioProject (Select 656167) - BioSample - NCBI](https://www.ncbi.nlm.nih.gov/biosample?LinkName=bioproject_biosample_all&from_uid=656167)
# 获得 AccessionID
注意，一次性最大好像只能保存200个 ID，需要多点2次保存。
![image.png|500](https://picturerealm.oss-cn-chengdu.aliyuncs.com/obsidian/20250603223806983.png)
保存到电脑内为一个 `txt` 文件：例如 `biosample_result.txt`：
```txt
SAMN15773089
SAMN15773088
SAMN15773087
SAMN15773086
SAMN15773085
SAMN15773084
```
# 软件准备
安装 `SRA Toolkit`，在服务器或者电脑安装：
```sh
# 进入任意目录，例如 $HOME/tools
cd ~/tools

# 下载最新版本（以 Linux x86_64 为例）
wget https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/current/sratoolkit.current-ubuntu64.tar.gz

# 解压并添加到环境变量（示例解压到 ~/tools/sratoolkit）
tar -zxvf sratoolkit.current-ubuntu64.tar.gz
export PATH=$PATH:~/tools/sratoolkit.*/bin

# 验证是否安装成功
which prefetch
which fasterq-dump
```
请根据自己操作系统（Ubuntu、CentOS、macOS 等）选择相应的下载包，并在 `~/.bashrc` 或 `~/.zshrc` 中持久化 `PATH`。
# 获取序列号
**以下以其中一个样本为例，多样本可以加个 `for` 循环或者 `parallel` 即可**。

> [!question] 这一步我发现不开网络代理得不到？

```sh
esearch -db biosample -query SAMN15773089 |   elink -target sra |   efetch -format runinfo > SAMN15773089_runinfo.csv
```
从生成的 `csv` 文件中找到了类似如下的内容：
```csv
Run,ReleaseDate,LoadDate,spots,bases,spots_with_mates,avgLength,size_MB,AssemblyName,download_path,Experiment,LibraryName,LibraryStrategy,LibrarySelection,LibrarySource,LibraryLayout,InsertSize,InsertDev,Platform,Model,SRAStudy,BioProject,Study_Pubmed_id,ProjectID,Sample,BioSample,SampleType,TaxID,ScientificName,SampleName,g1k_pop_code,source,g1k_analysis_group,Subject_ID,Sex,Disease,Tumor,Affection_Status,Analyte_Type,Histological_Type,Body_Site,CenterName,Submission,dbgap_study_accession,Consent,RunHash,ReadHash
SRR12420819,2021-04-09 22:21:30,2020-08-10 10:37:33,2710081,813024300,2710081,300,276,,https://sra-downloadb.be-md.ncbi.nlm.nih.gov/sos9/sra-pub-zq-924/SRR012/12420/SRR12420819/SRR12420819.lite.1,SRX8916460,XZ10240,WGS,RANDOM PCR,GENOMIC,PAIRED,0,0,ILLUMINA,Illumina HiSeq 2500,SRP276868,PRJNA656167,,656167,SRS7173032,SAMN15773089,simple,1773,Mycobacterium tuberculosis,p576,,,,,,,no,,,,,FUDAN UNIVERSITY,SRA1110644,,public,320B7839BC9F351604C1239B89AD64E3,F5BE30E784A4F88995F1BAB56068FD0C
```
其中的 `SRR12420819` 即为下载序列号。

# 下载
**不需要开启网络代理**，不然耗费流量。
```sh
prefetch SRR12420819
```
会自动在当前目录创建一个文件夹。然后开始自动下载。
不开代理速度还是很快的：
![image.png|500](https://picturerealm.oss-cn-chengdu.aliyuncs.com/obsidian/20250603225559427.png)

# 格式转化
下载出来的文件通过如下命令转为 `fastq` 文件：
```sh
fasterq-dump SRR12420819
```

