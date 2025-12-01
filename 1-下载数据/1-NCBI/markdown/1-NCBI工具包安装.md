# 1. 安装前置（Ubuntu/WSL 例子）
sudo apt update
sudo apt install -y wget perl gzip

# 2. 下载并运行官方安装脚本（会装到 ~/edirect）
cd $HOME
sh -c "$(curl -fsSL https://ftp.ncbi.nlm.nih.gov/entrez/entrezdirect/install-edirect.sh)"

# 3. 把 edirect 加到 PATH（临时）
export PATH="$HOME/edirect:$PATH"

# 永久加到 shell 启动文件，例如 ~/.bashrc 或 ~/.profile
echo 'export PATH="$HOME/edirect:$PATH"' >> ~/.bashrc
source ~/.bashrc
