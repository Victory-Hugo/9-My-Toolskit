#!/usr/bin/env bash
# ============================================================
# Aspera CLI 下载 ENA 数据配置与执行脚本
# ============================================================

# 1. 安装 Ruby 与 aspera-cli（如未安装）
sudo apt update
sudo apt install -y ruby-full
sudo gem install aspera-cli

# 2. 创建或更新预设（preset）
# 注意修改 ssh_keys 路径为你自己的密钥文件路径
ascli conf preset update era \
  --url=ssh://fasp.sra.ebi.ac.uk:33001 \
  --username=era-fasp \
  --ssh-keys="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/2-ENA/conf/asperaweb_id_dsa.openssh" \
  --ts=@json:'{"target_rate_kbps":0}'

# 或者（如果不使用 ssh 密钥文件）
# ascli conf preset update era \
#   --url=ssh://fasp.sra.ebi.ac.uk:33001 \
#   --username=era-fasp \
#   --ts=@json:'{"target_rate_kbps":300000}'

# 3. 查看配置是否成功
ascli conf preset show era

# 示例输出：
# ╭─────────────────────┬────────────────────────────────╮
# │ field               │ value                          │
# ╞═════════════════════╪════════════════════════════════╡
# │ url                 │ ssh://fasp.sra.ebi.ac.uk:33001 │
# │ username            │ era-fasp                       │
# │ ssh_keys            │ 🔑                             │
# │ ts.target_rate_kbps │ 300000                         │
# ╰─────────────────────┴────────────────────────────────╯

# 4. 下载示例文件
# -Pera 表示使用 era 预设配置
# ascli -Pera server download \
#   vol1/fastq/SRR916/002/SRR9169172/SRR9169172.fastq.gz \
#   --to-folder=/mnt/c/Users/Administrator/Desktop/
