import os
import requests
import pandas as pd
from concurrent.futures import ThreadPoolExecutor

# 读取 list.txt 中的 accessions
list_file_path = r'C:/Users/victo/Desktop/list.txt'

# 获取桌面路径
desktop_path = os.path.join(os.path.expanduser("~"), "Desktop")

# 确保 list.txt 文件存在
if not os.path.exists(list_file_path):
    print(f"文件 {list_file_path} 不存在，请检查路径。")
else:
    # 逐行读取 list.txt 文件中的 accessions
    with open(list_file_path, 'r') as f:
        accessions = [line.strip() for line in f.readlines() if line.strip()]

    # ENA API URL
    url = 'https://www.ebi.ac.uk/ena/portal/api/filereport'
    
    # 创建保存文件的路径
    output_file_path = os.path.join(desktop_path, 'all_metadata.tsv')

    # 检查文件是否已经存在
    file_exists = os.path.exists(output_file_path)

    # 定义处理单个 accession 的函数
    def fetch_data_for_accession(accession):
        params = {
            'accession': accession,      # 使用每个读取到的 accession
            'result': 'read_run',        # 获取读数的结果
            'format': 'tsv',             # 返回 tsv 格式的数据
        }

        try:
            response = requests.get(url, params=params)

            # 如果请求成功，处理返回的结果
            if response.status_code == 200:
                data = response.text
                return data
            else:
                print(f"请求 {accession} 失败，状态码：{response.status_code}")
                return None
        except requests.exceptions.RequestException as e:
            print(f"请求 {accession} 时出错: {e}")
            return None

    # 使用 ThreadPoolExecutor 来并发执行任务
    with ThreadPoolExecutor(max_workers=50) as executor:
        results = executor.map(fetch_data_for_accession, accessions)

    # 将所有返回的数据合并并写入文件
    with open(output_file_path, 'a') as output_file:
        for result in results:
            if result:
                output_file.write(result)
    
    print(f"所有元数据已保存到文件: {output_file_path}")

    # 进行去重操作
    # 读取文件内容，去掉重复的行
    if os.path.exists(output_file_path):
        with open(output_file_path, 'r') as file:
            lines = file.readlines()

        # 使用集合来跟踪已经出现的行
        seen = set()
        unique_lines = []

        for line in lines:
            if line not in seen:
                unique_lines.append(line)
                seen.add(line)

        # 将去重后的内容重新写入文件
        with open(output_file_path, 'w') as file:
            file.writelines(unique_lines)

        print(f"去重后的数据已保存到文件: {output_file_path}")


# 读取文件并生成命令
df_metafile = pd.read_csv(output_file_path, sep='\t')
df_ftp = df_metafile.loc[:, ['sra_ftp']]
df_ftp['ftp_command'] = 'wget -nc '
df_ftp['http_command'] = 'http://'

# 创建 ftp 和 http 链接
df_ftp['ftp_link_ftp'] = df_ftp['ftp_command'].str.cat(df_ftp['sra_ftp'])
df_ftp['ftp_link_ftp'].to_csv('ftp_links.csv', index=False, header=False)

df_ftp['ftp_link_http'] = df_ftp['http_command'].str.cat(df_ftp['sra_ftp'])
df_ftp['ftp_link_http'].to_csv('http_links.csv', index=False, header=False)
