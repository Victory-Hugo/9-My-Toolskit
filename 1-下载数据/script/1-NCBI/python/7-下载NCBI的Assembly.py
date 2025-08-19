#!/usr/bin/env python3
# coding: utf-8
"""
批量下载 NCBI Datasets 数据（已配置默认邮箱和 API Key）

使用方法示例：
  export NCBI_API_KEY="..."      # 可选：覆盖脚本内默认
  export NCBI_EMAIL="..."        # 可选：覆盖脚本内默认
  python3 download_datasets.py -b /mnt/c/Users/Administrator/Desktop/ -f /path/to/下载NCBI.txt -w 5
"""
import os
import argparse
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
import time
from urllib.parse import urlparse, parse_qs, urlencode, urlunparse

# -------------------- 默认配置（可通过环境变量或命令行覆盖） --------------------
DEFAULT_NCBI_EMAIL = os.environ.get("NCBI_EMAIL", "giantlinlinlin@gmail.com")
DEFAULT_NCBI_API_KEY = os.environ.get("NCBI_API_KEY", "29b326d54e7a21fc6c8b9afe7d71f441d809")
# -------------------------------------------------------------------------------

# 全局速率控制（会在 main 中根据是否有 key 调整 allowed_rps）
RATE_LOCK = threading.Lock()
LAST_REQUEST_TIME = 0.0
MIN_INTERVAL = 0.0  # 每次请求最小间隔秒，之后在 main() 中计算

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
    parser.add_argument(
        "--email", "-e",
        default=DEFAULT_NCBI_EMAIL,
        help=f"联系邮箱（默认: {DEFAULT_NCBI_EMAIL}）"
    )
    parser.add_argument(
        "--api-key", "-k",
        default=DEFAULT_NCBI_API_KEY,
        help=f"NCBI API Key（默认已内置）"
    )
    parser.add_argument(
        "--workers", "-w",
        type=int,
        default=5,
        help="并发线程数（默认5）"
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
    )
    return [URL_TEMPLATE.format(acc) for acc in accession_numbers]

def append_api_key_to_url(url, api_key):
    """
    如果 api_key 非空且 URL 中还没有 api_key 参数，则追加 api_key 参数并返回新的 URL。
    """
    if not api_key:
        return url
    parsed = urlparse(url)
    qs = parse_qs(parsed.query)
    if "api_key" in qs and qs["api_key"]:
        return url  # 已有 api_key，直接返回
    qs["api_key"] = [api_key]
    new_query = urlencode(qs, doseq=True)
    new_parsed = parsed._replace(query=new_query)
    return urlunparse(new_parsed)

def rate_limit_wait():
    """
    全局速率限制：确保线程间的请求间隔至少为 MIN_INTERVAL 秒
    """
    global LAST_REQUEST_TIME
    with RATE_LOCK:
        now = time.time()
        elapsed = now - LAST_REQUEST_TIME
        if elapsed < MIN_INTERVAL:
            to_sleep = MIN_INTERVAL - elapsed
            time.sleep(to_sleep)
            LAST_REQUEST_TIME = time.time()
        else:
            LAST_REQUEST_TIME = now

def create_session(email):
    """
    创建共享的 requests.Session，带 retry 策略和常用 headers（包含 email）
    """
    session = requests.Session()
    retry_strategy = Retry(
        total=5,
        backoff_factor=1,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"]
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("https://", adapter)
    # 将 email 放入 User-Agent 和 From header（不少机构希望看到 contact）
    ua = f"ncbi-datasets-downloader ({email})"
    session.headers.update({
        "User-Agent": ua,
        "From": email
    })
    return session

def download_file(session, url, output_filename, api_key):
    """
    下载单个文件（stream），在每次请求前做全局速率限制，并返回结果字符串
    """
    try:
        final_url = append_api_key_to_url(url, api_key)
        # 全局速率限制
        rate_limit_wait()
        # 发起请求（流式）
        with session.get(final_url, stream=True, timeout=60) as response:
            if response.status_code == 200:
                # 临时写入文件（避免半截文件被误判为成功）
                tmp_out = output_filename + ".part"
                with open(tmp_out, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=1024*16):
                        if chunk:
                            f.write(chunk)
                # 下载成功后重命名
                os.replace(tmp_out, output_filename)
                return f"成功: {output_filename}"
            else:
                return f"失败: {url} (状态码: {response.status_code})"
    except Exception as e:
        return f"失败: {url} (错误: {e})"

def concurrent_download(urls, base_path, success_file, failure_file, api_key, workers, email):
    os.makedirs(base_path, exist_ok=True)
    session = create_session(email)
    with ThreadPoolExecutor(max_workers=workers) as executor, \
         open(success_file, 'w', encoding='utf-8') as sf, \
         open(failure_file, 'w', encoding='utf-8') as ff:
        future_to_url = {}
        for url in urls:
            # accession 从 URL 提取（模板固定，倒数第二段）
            try:
                acc = url.split("/")[-2]
            except Exception:
                acc = "unknown"
            out_fname = os.path.join(base_path, f"{acc}_downloaded.zip")
            future = executor.submit(download_file, session, url, out_fname, api_key)
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
    global MIN_INTERVAL
    args = parse_args()

    BASE_PATH = args.base_path.rstrip("/") + "/"
    FILE_PATH = args.file_path
    EMAIL = args.email
    API_KEY = args.api_key
    WORKERS = max(1, args.workers)

    OUTPUT_FILE  = os.path.join(BASE_PATH, "generated_urls.txt")
    SUCCESS_FILE = os.path.join(BASE_PATH, "success.txt")
    FAILURE_FILE = os.path.join(BASE_PATH, "failure.txt")

    os.makedirs(BASE_PATH, exist_ok=True)

    # 根据是否有 API Key 设置允许的全局 rps（你可以按需调节）
    if API_KEY:
        ALLOWED_RPS = 10.0   # 带 key 的建议速率（可根据实际情况降级）
    else:
        ALLOWED_RPS = 3.0    # 无 key 更保守
    # 计算最小间隔（多个并发线程共享）
    # 目标：全系统平均速率不超过 ALLOWED_RPS
    # 每个请求之间的最小间隔 = 并发线程数 / ALLOWED_RPS
    MIN_INTERVAL = float(WORKERS) / float(ALLOWED_RPS)

    # 1. 读取 accession 列表，并生成 URL
    accession_numbers = read_accession_file(FILE_PATH)
    urls = generate_urls(accession_numbers)

    # 2. 保存 URL 列表（在保存的 URL 中不自动追加 api_key，实际请求时会追加）
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as outf:
        for u in urls:
            outf.write(u + "\n")
    print(f"下载链接已保存至 {OUTPUT_FILE}")

    # 3. 并发下载
    concurrent_download(urls, BASE_PATH, SUCCESS_FILE, FAILURE_FILE, API_KEY, WORKERS, EMAIL)
    print(f"下载完成！成功记录：{SUCCESS_FILE}，失败记录：{FAILURE_FILE}")

if __name__ == "__main__":
    main()
