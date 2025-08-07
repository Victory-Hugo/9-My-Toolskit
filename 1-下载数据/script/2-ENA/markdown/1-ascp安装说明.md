# 前言
`Aspera`是一款高性能的文件传输工具，广泛应用于大数据传输场景。

>但是其版本管理就是一坨屎，版本号不规范，文档不全，安装配置麻烦。

# 安装
亲测有效，**不要使用最新版**！
亲测有效，**不要使用最新版**！
亲测有效，**不要使用最新版**！

# Linux
在`Linux`环境下，十分推荐用`conda`安装。
注意到，请安装版本为`ascp version 3.9.1.168954`的版本，该版本可以下载`NCBI`,`ENA`及`CNCB`的数据，比较方便和稳定。

你可以通过 Conda（最好是 Bioconda 频道）来安装指定版本的 `ascp`（Aspera Secure Copy）。假设该包在 Bioconda 上叫做 `aspera` 或 `ascp`，安装步骤大致如下：

1. **添加必要的频道**
   ```bash
   conda config --add channels defaults
   conda config --add channels bioconda
   conda config --add channels conda-forge
   ```

2. **搜索可用的包名及版本**
   先确认包名及可用版本：

   ```bash
   conda search -c bioconda ascp
   # 或者
   conda search -c bioconda aspera
   ```

   如果看到类似 `3.9.1.168954` 的条目，说明该版本在仓库中可用。

3. **安装指定版本**
   假设包名是 `aspera`，命令如下：
   ```bash
   conda install -c bioconda aspera=3.9.1.168954
   ```

   如果包名是 `ascp`，则改为：
   ```bash
   conda install -c bioconda ascp=3.9.1.168954
   ```

4. **验证安装**
   安装完成后，执行：
   ```bash
   ascp --version
   ```

   应该会输出：
   ```
   ascp version 3.9.1.168954
   ```

