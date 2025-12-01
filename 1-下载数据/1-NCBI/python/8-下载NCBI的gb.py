from Bio import Entrez, SeqIO
from concurrent.futures import ThreadPoolExecutor, as_completed
import os

# 设置您的邮箱地址
Entrez.email = "giantlinlinlin@gmail.com"

# 指定保存文件的目录
save_directory = r"F:/OneDrive/文档（科研）/脚本/我的科研脚本/Python/数据科学/下载序列"
os.makedirs(save_directory, exist_ok=True)

# 初始化日志文件
success_log_file = os.path.join(save_directory, "success_log.txt")
failure_log_file = os.path.join(save_directory, "failure_log.txt")

# 定义函数以下载序列并提取特征信息
def download_and_process_sequence(seq_id):
    try:
        # 下载fasta序列
        handle_fasta = Entrez.efetch(db="nucleotide", id=seq_id, rettype="fasta", retmode="text")
        record_fasta = SeqIO.read(handle_fasta, "fasta")
        handle_fasta.close()

        # 保存fasta文件
        filename_fasta = f"{save_directory}\\{seq_id}.fasta"
        SeqIO.write(record_fasta, filename_fasta, "fasta")
        print(f"Downloaded and saved {filename_fasta}")

        # 下载genbank记录以提取特征信息
        handle_gb = Entrez.efetch(db="nucleotide", id=seq_id, rettype="gb", retmode="text")
        record_gb = SeqIO.read(handle_gb, "genbank")
        country = isolate = lat_lon = "Not Available"
        for feature in record_gb.features:
            if feature.type == "source":
                qualifiers = feature.qualifiers
                country = qualifiers.get("country", ["Not Available"])[0]
                isolate = qualifiers.get("isolate", ["Not Available"])[0]
                lat_lon = qualifiers.get("lat_lon", ["Not Available"])[0]
                break

        reference_titles = ", ".join([ref.title for ref in record_gb.annotations.get("references", []) if ref.title])
        with open(f"F:/OneDrive/文档（科研）/脚本/我的科研脚本/Python/数据科学/下载序列/基本信息.txt", "a") as output_file:
            output_file.write(f"{seq_id}\t{country}\t{isolate}\t{lat_lon}\t{reference_titles}\n")
        print(f"{seq_id}\t信息已经打印！")
        handle_gb.close()

        # 保存GenBank格式文件 (.gb)
        filename_gb = f"{save_directory}\\{seq_id}.gb"
        SeqIO.write(record_gb, filename_gb, "genbank")
        print(f"Downloaded and saved {filename_gb}")

        # 如果成功，记录到成功日志
        with open(success_log_file, "a") as success_log:
            success_log.write(f"{seq_id}\n")

    except Exception as e:
        print(f"Error processing {seq_id}: {str(e)}")

        # 如果失败，记录到失败日志
        with open(failure_log_file, "a") as failure_log:
            failure_log.write(f"{seq_id}\t{str(e)}\n")

# 从同一个文件读取序列ID
id_list = []
with open("F:/OneDrive/文档（科研）/脚本/我的科研脚本/Python/数据科学/下载NCBI.txt", "r") as file:
    for line in file:
        id_list.append(line.strip())

# 使用线程池并行下载和处理序列
with ThreadPoolExecutor(max_workers=5) as executor:
    futures = [executor.submit(download_and_process_sequence, seq_id) for seq_id in id_list]

    for future in as_completed(futures):
        future.result()  # 检查是否有异常

print("所有序列处理完成。")
