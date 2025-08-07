#!/usr/bin/env python3
# coding: utf-8

import os
import argparse
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from concurrent.futures import ThreadPoolExecutor, as_completed

def parse_args():
    parser = argparse.ArgumentParser(description="批量下载 NCBI Datasets 数据")
    parser.add_argument(
        "--base-path", "-b",
        required=True,
        help="输出结果和下载文件的基础路径，例如 /mnt/c/Users/Administrator/Desktop/"
    )
    parser.add_argument(
        "--file-path", "-f",
        required=True,
        help="存放 accession 列表的文本文件路径，例如 /path/to/下载NCBI.txt"
    )
    return parser.parse_args()

def read_accession_file(file_path):
    with open(file_path, 'r', encoding='utf-8') as file:
        return [accession.strip() for accession in file if accession.strip()]

def generate_urls(accession_numbers):
    URL_TEMPLATE = (
        "https://api.ncbi.nlm.nih.gov/datasets/v2/genome/accession/{}/download"
        "?include_annotation_type=GENOME_FASTA"
        "&include_annotation_type=GENOME_GFF"
        "&include_annotation_type=CDS_FASTA"
        # "&include_annotation_type=RNA_FASTA"
        # "&include_annotation_type=PROT_FASTA"
        # "&include_annotation_type=SEQUENCE_REPORT"
    )
    return [URL_TEMPLATE.format(acc) for acc in accession_numbers]

def download_file(url, output_filename):
    try:
        session = requests.Session()
        retry_strategy = Retry(
            total=5,
            backoff_factor=1,
            status_forcelist=[500, 502, 503, 504],
            allowed_methods=["GET"]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("https://", adapter)

        response = session.get(url, stream=True, timeout=30)
        if response.status_code == 200:
            with open(output_filename, 'wb') as f:
                for chunk in response.iter_content(chunk_size=1024):
                    if chunk:
                        f.write(chunk)
            return f"成功: {output_filename}"
        else:
            return f"失败: {url} (状态码: {response.status_code})"
    except Exception as e:
        return f"失败: {url} (错误: {e})"

def concurrent_download(urls, base_path, success_file, failure_file):
    os.makedirs(base_path, exist_ok=True)
    with ThreadPoolExecutor(max_workers=5) as executor, \
         open(success_file, 'w', encoding='utf-8') as sf, \
         open(failure_file, 'w', encoding='utf-8') as ff:
        future_to_url = {}
        for url in urls:
            acc = url.split("/")[-2]
            out_fname = os.path.join(base_path, f"{acc}_downloaded.zip")
            future = executor.submit(download_file, url, out_fname)
            future_to_url[future] = url

        for future in as_completed(future_to_url):
            result = future.result()
            if result.startswith("成功"):
                print(result)
                sf.write(result + "\n")
            else:
                print(result)
                ff.write(result + "\n")

def main():
    args = parse_args()

    BASE_PATH = args.base_path.rstrip("/") + "/"
    FILE_PATH = args.file_path

    OUTPUT_FILE  = os.path.join(BASE_PATH, "generated_urls.txt")
    SUCCESS_FILE = os.path.join(BASE_PATH, "success.txt")
    FAILURE_FILE = os.path.join(BASE_PATH, "failure.txt")

    os.makedirs(BASE_PATH, exist_ok=True)

    # 1. 读取 accession 列表，并生成 URL
    accession_numbers = read_accession_file(FILE_PATH)
    urls = generate_urls(accession_numbers)

    # 2. 保存 URL 列表
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as outf:
        for u in urls:
            outf.write(u + "\n")
    print(f"下载链接已保存至 {OUTPUT_FILE}")

    # 3. 并发下载
    concurrent_download(urls, BASE_PATH, SUCCESS_FILE, FAILURE_FILE)
    print(f"下载完成！成功记录：{SUCCESS_FILE}，失败记录：{FAILURE_FILE}")

if __name__ == "__main__":
    main()
