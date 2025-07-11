import os
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from concurrent.futures import ThreadPoolExecutor, as_completed

# 配置常量
BASE_PATH = r'D:/幽门螺旋杆菌'
FILE_PATH = r'F:/OneDrive/文档（科研）/脚本/我的科研脚本/Python/数据科学/下载NCBI.txt'
OUTPUT_FILE = os.path.join(BASE_PATH, 'generated_urls.txt')
SUCCESS_FILE = os.path.join(BASE_PATH, 'success.txt')
FAILURE_FILE = os.path.join(BASE_PATH, 'failure.txt')

URL_TEMPLATE = 'https://api.ncbi.nlm.nih.gov/datasets/v2/genome/accession/{}/download?include_annotation_type=GENOME_FASTA' \
    # '&include_annotation_type=GENOME_GFF' \
    # '&include_annotation_type=RNA_FASTA' \
    # '&include_annotation_type=CDS_FASTA' \
    # '&include_annotation_type=PROT_FASTA' \
    # '&include_annotation_type=SEQUENCE_REPORT' \
    # '&hydrated=FULLY_HYDRATED'

# 创建路径文件夹（如果不存在的话）
os.makedirs(BASE_PATH, exist_ok=True)

# 读取文件获取所有的accession
def read_accession_file(file_path):
    with open(file_path, 'r') as file:
        return [accession.strip() for accession in file.readlines()]

# 生成URL
def generate_urls(accession_numbers):
    return [URL_TEMPLATE.format(accession) for accession in accession_numbers]

# 下载文件
def download_file(url, output_filename):
    try:
        # 创建会话并设置重试策略
        session = requests.Session()
        retry_strategy = Retry(
            total=5,  # 最多重试5次
            backoff_factor=1,  # 重试间隔（秒）
            status_forcelist=[500, 502, 503, 504],  # 这些状态码会触发重试
            allowed_methods=["GET"]  # 使用'allowed_methods'代替'method_whitelist'
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("https://", adapter)

        # 发送下载请求
        response = session.get(url, stream=True)

        # 成功下载
        if response.status_code == 200:
            with open(output_filename, 'wb') as file:
                for chunk in response.iter_content(chunk_size=1024):
                    if chunk:
                        file.write(chunk)
            return f"成功: {output_filename}"

        # 下载失败
        else:
            return f"失败: {url} (状态码: {response.status_code})"

    except requests.exceptions.RequestException as e:
        return f"失败: {url} (错误: {e})"

# 并发下载
def concurrent_download(urls):
    with ThreadPoolExecutor(max_workers=5) as executor:
        future_to_url = {
            executor.submit(download_file, url, os.path.join(BASE_PATH, f'{url.split("/")[-2]}_downloaded_file.zip')): url
            for url in urls
        }

        # 打开成功和失败文件进行写入
        with open(SUCCESS_FILE, 'w') as success_f, open(FAILURE_FILE, 'w') as failure_f:
            for future in as_completed(future_to_url):
                result = future.result()
                if "成功" in result:
                    print(f'成功下载了{result}')
                    success_f.write(result + '\n')
                else:
                    print(f'下载失败了{result}')
                    failure_f.write(result + '\n')

# 主函数
def main():
    # 读取文件并生成URL
    accession_numbers = read_accession_file(FILE_PATH)
    urls = generate_urls(accession_numbers)

    # 将URL保存到文件
    with open(OUTPUT_FILE, 'w') as file:
        for url in urls:
            file.write(url + '\n')
    print(f"下载的链接已经被保存至{OUTPUT_FILE}")

    # 开始并发下载
    concurrent_download(urls)

    print(f"下载完成！成功文件记录在 {SUCCESS_FILE}，失败文件记录在 {FAILURE_FILE}。")

if __name__ == "__main__":
    main()
