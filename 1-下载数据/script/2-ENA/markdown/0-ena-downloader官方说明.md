```
/*******************************************************************************
* 版权所有 2021 EMBL-EBI，Hinxton 分站
*
* 根据 Apache 许可证 2.0 版（“许可证”）授权；除非符合许可证，否则您不得使用此文件。
* 您可以通过以下地址获得许可证副本：
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* 除非适用法律要求或书面同意，否则按“原样”分发本软件；无任何明示或暗示的保证或条件。
* 有关许可证下权限和限制的具体语言，请参阅许可证。
*******************************************************************************
```

**版本**：1.1.10

# Ena 文件下载工具

**版权** © EMBL 2021 | EMBL-EBI 是欧洲分子生物学实验室 (EMBL) 的一部分

如需支持/反馈，请访问：https://www.ebi.ac.uk/ena/browser/support

---

## 使用方式

有两种运行工具的方式：

1. **交互式**：首次运行时使用，浏览可用选项并生成简单脚本，之后可直接调用  
   ```bash
   java -jar ena-file-downloader.jar
   ```  
   或调用提供的便捷脚本。

   **Linux/Unix**：
   ```bash
   ./run.sh
   # 如有必要，可赋予可执行权限：
   chmod +x run.sh
   ```

   **Windows**：
   ```bat
   run.bat
   ```

2. **命令行参数模式**：在控制台直接提供参数运行

   - **通过 accession 列表**  
     ```bash
     java -jar ena-file-downloader.jar \
       --accessions=SAMEA3231268,SAMEA3231287 \
       --format=READS_FASTQ \
       --location=C:\Users\Documents\ena \
       --protocol=FTP \
       --asperaLocation=null \
       --email=email@youremail.com
     ```

   - **通过查询**  
     ```bash
     java -jar ena-file-downloader.jar \
       --query="result=read_run&query=country=%22Japan%22AND%20depth=168" \
       --format=READS_FASTQ \
       --location="C:\Users\Documents\ena ebi" \
       --protocol=FTP \
       --asperaLocation=null \
       --email=email@youremail.com
     ```

3. **从aspera下载**  
   ```bash
   java -jar ena-file-downloader.jar \
     --accessions=SAMEA3231268,SAMEA3231287 \
     --format=READS_FASTQ \
     --location=C:\Users\Documents\ena \
     --protocol=FTP \
     --asperaLocation=null \
     --email=email@youremail.com \
     --dataHubUsername=dcc_abc \
     --dataHubPassword=*****
   ```

---

## 参数说明

- `--query`  
  下载查询语句，包含 result 和 query 部分  
  ```text
  eg: result=read_run&query=country="Japan"AND depth=168
  ```
- `--accessions`  
  逗号分隔的 accession 列表，或指向 accession 列表的文件路径。  
  - 文件应为纯文本 TSV（制表符分隔）格式。  
  - 如有多列，第一列必须是 accession。  
  - 可有表头，会被忽略。  
  - 值可加双引号，也可不加。

- `--format`  
  下载格式，例如：  
  `READS_FASTQ`, `READS_SUBMITTED`, `READS_BAM`, `ANALYSIS_SUBMITTED`, `ANALYSIS_GENERATED`

- `--location`  
  下载保存目录

- `--protocol`  
  下载协议，例如：FTP（默认）、ASPERA

- `--asperaLocation`  
  本地 Aspera Connect/CLI 安装目录。若使用 Aspera 协议则必填。

- `--email`  
  接受提醒的邮箱（可选）

- `--dataHubUsername`  
  数据中心用户名（仅当从数据中心下载时需要）

- `--dataHubPassword`  
  数据中心密码（仅当从数据中心下载时需要）

> **注意**：如参数值中包含空格，请使用双引号括起，例如：  
> ```bash
> --location="C:\Users\Documents\ena ebi"
> ```

---

## 快速入门

### 构建

1. 安装 JDK8  
2. 使用 Gradle Wrapper 构建项目：
   ```bash
   ./gradlew build
   ```
3. 构建完成的 Jar 包位于：`build/libs/`

### 日志

应用日志将写入：`logs/app.log`

---

## 隐私声明

执行此工具时可能需有限度地处理您的个人数据。使用本工具即表示您同意以下内容：  
- 隐私声明：https://www.ebi.ac.uk/data-protection/privacy-notice/ena-presentation  
- 使用条款：https://www.ebi.ac.uk/about/terms-of-use

---

**本软件由 EMBL-EBI 开发并按“原样”分发。**  
**许可证**：https://www.apache.org/licenses/LICENSE-2.0
