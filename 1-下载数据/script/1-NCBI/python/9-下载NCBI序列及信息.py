import os
from Bio import Entrez, SeqIO
from concurrent.futures import ThreadPoolExecutor, as_completed

# ——————— 配置部分 ———————
Entrez.email         = "giantlinlinlin@gmail.com"
save_directory       = r"/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/1-下载数据/download"
os.makedirs(save_directory, exist_ok=True)
success_log_file     = os.path.join(save_directory, "success_log.txt")
failure_log_file     = os.path.join(save_directory, "failure_log.txt")
basic_info_file      = os.path.join(save_directory, "基本信息.txt")
conf_file            = os.path.join(os.path.dirname(save_directory), "conf", "下载NCBI.txt")


def download_and_process_sequence(seq_id):
    try:
        # —— 下载并解析 FASTA —— 
        raw_fasta = Entrez.efetch(db="nucleotide",
                                  id=seq_id,
                                  rettype="fasta",
                                  retmode="text")
        # 用 fasta-pearson 格式，允许前置注释
        fasta_records = list(SeqIO.parse(raw_fasta, "fasta-pearson"))
        raw_fasta.close()

        if not fasta_records:
            raise ValueError("No FASTA record found")
        record_fasta = fasta_records[0]

        # 保存 FASTA 文件
        fasta_path = os.path.join(save_directory, f"{seq_id}.fasta")
        SeqIO.write(record_fasta, fasta_path, "fasta")
        print(f"[FASTA] 已保存：{fasta_path}")

        # —— 下载并解析 GenBank —— 
        raw_gb = Entrez.efetch(db="nucleotide",
                               id=seq_id,
                               rettype="gb",
                               retmode="text")
        gb_records = list(SeqIO.parse(raw_gb, "genbank"))
        raw_gb.close()

        if not gb_records:
            raise ValueError("No GenBank record found")
        record_gb = gb_records[0]

        # 提取 source feature 信息
        country = isolate = lat_lon = "Not Available"
        for feat in record_gb.features:
            if feat.type == "source":
                qs = feat.qualifiers
                country  = qs.get("country",  ["Not Available"])[0]
                isolate  = qs.get("isolate",  ["Not Available"])[0]
                lat_lon  = qs.get("lat_lon",  ["Not Available"])[0]
                break

        # 提取参考文献标题
        refs = record_gb.annotations.get("references", [])
        titles = [r.title for r in refs if r.title]
        titles_str = ", ".join(titles) if titles else "None"

        # 记录到“基本信息.txt”
        with open(basic_info_file, "a", encoding="utf-8") as out:
            out.write(f"{seq_id}\t{country}\t{isolate}\t{lat_lon}\t{titles_str}\n")
        print(f"[INFO] {seq_id} 已追加至基本信息文件")

        # 成功日志
        with open(success_log_file, "a", encoding="utf-8") as log:
            log.write(seq_id + "\n")

    except Exception as e:
        # 打印错误并写入失败日志
        print(f"[ERROR] {seq_id}: {e}")
        with open(failure_log_file, "a", encoding="utf-8") as log:
            log.write(f"{seq_id}\t{e}\n")


if __name__ == "__main__":
    # 读取 seq_id 列表
    with open(conf_file, "r", encoding="utf-8") as f:
        id_list = [line.strip() for line in f if line.strip()]

    # 并行下载处理
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = [executor.submit(download_and_process_sequence, sid) for sid in id_list]
        for future in as_completed(futures):
            try:
                future.result()
            except Exception:
                pass  # 已在函数内部处理过

    print("所有序列处理完成。")
