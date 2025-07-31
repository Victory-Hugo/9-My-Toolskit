from Bio import Entrez, SeqIO

# 设置您的邮箱地址
Entrez.email = "your_email@example.com"

# 指定保存文件的目录
save_directory = r"F:/OneDrive/文档（科研）/脚本/我的科研脚本/Python/数据科学/下载序列"

# 定义函数以仅提取特征信息
def extract_sequences_info(id_list):
    for seq_id in id_list:
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
        with open(f"{save_directory}/信息.txt", "a") as output_file:
            output_file.write(f"{seq_id}\t{country}\t{isolate}\t{lat_lon}\t{reference_titles}\n")
        print(f"{seq_id}\t信息已经打印！")
        handle_gb.close()

# 从同一个文件读取序列ID
id_list = []
with open("F:/OneDrive/文档（科研）/脚本/我的科研脚本/Python/数据科学/下载NCBI.txt", "r") as file:
    for line in file:
        id_list.append(line.strip())

# 调用函数
extract_sequences_info(id_list)
