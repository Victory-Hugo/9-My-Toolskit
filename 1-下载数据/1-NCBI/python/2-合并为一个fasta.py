import os

# 定义文件目录路径
directory = r'/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/script/1-NCBI/download'
#directory = r'C:/Users/victo/Desktop'
# 定义输出文件路径
output_file = os.path.join('/mnt/c/Users/Administrator/Desktop', 'merged_sequences.fasta')

# 打开输出文件，准备写入
with open(output_file, 'w') as outfile:
    # 遍历目录下的所有文件
    for filename in os.listdir(directory):
        # 检查文件是否为.fasta文件
        if filename.endswith('.fasta'):
            filepath = os.path.join(directory, filename)
            # 打开每个.fasta文件
            with open(filepath, 'r') as infile:
                # 将文件内容写入输出文件
                outfile.write(infile.read())
                outfile.write('\n')  # 添加换行符以确保文件内容分隔

print(f"所有.fasta文件已合并到: {output_file}")

from Bio import SeqIO
import os
import glob

# 桌面路径，假设是默认桌面路径。请根据实际路径修改。
desktop_path = os.path.expanduser("C:/Users/victo/Desktop")

# 找到桌面上所有fasta文件
fasta_files = glob.glob(os.path.join(desktop_path, "*.fasta"))

# 清理函数
def clean_fasta_ids_in_place(file_path):
    # 创建临时文件用于写入清理后的内容
    temp_file = file_path + ".tmp"
    
    with open(temp_file, "w") as output_handle:
        for record in SeqIO.parse(file_path, "fasta"):
            # 提取并清理ID，仅保留第一个空格前的部分
            record.id = record.id.split(" ")[0]
            record.description = ""  # 清空描述
            SeqIO.write(record, output_handle, "fasta")
    
    # 替换原文件
    os.replace(temp_file, file_path)

# 依次清理每个fasta文件
for fasta_file in fasta_files:
    clean_fasta_ids_in_place(fasta_file)

print("所有FASTA文件已清理完毕，并替换原文件。")
