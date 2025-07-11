import os
import pandas as pd
import requests

# 定义CSV文件路径
csv_file_path = r'C:/Users/victo/Desktop/下载详情.csv'

# 定义保存文件的目录
download_dir = r'C:/Users/victo/Desktop/古代DNA'
os.makedirs(download_dir, exist_ok=True)

# 读取CSV文件
df = pd.read_csv(csv_file_path)

# 获取“ftpPathDna”列的所有链接
urls = df['ftpPathDna'].tolist()

# 下载文件
for url in urls:
    file_name = os.path.join(download_dir, url.split('/')[-1])
    print(f"Downloading {file_name}...")
    try:
        response = requests.get(url)
        response.raise_for_status()  # 检查请求是否成功
        with open(file_name, 'wb') as file:
            file.write(response.content)
        print(f"{file_name} downloaded successfully.")
    except requests.exceptions.RequestException as e:
        print(f"Failed to download {file_name}. Error: {e}")

print("All files downloaded.")
