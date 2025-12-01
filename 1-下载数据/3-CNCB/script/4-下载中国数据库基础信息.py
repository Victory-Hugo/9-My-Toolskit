import requests
import csv

# 输入和输出文件路径
input_file = r'C:/Users/victo/Desktop/新建 Text Document.txt'
output_file = r'C:/Users/victo/Desktop/下载详情.csv'

# 打开输出文件
with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
    # 创建CSV写入对象
    csvwriter = csv.writer(csvfile)
    
    # 初始化标志，确保表头只写入一次
    header_written = False
    
    # 读取ID列表并逐个处理
    with open(input_file, 'r') as file:
        for id in file:
            id = id.strip()  # 去除ID前后的空白字符（如换行符）
            if id:  # 如果ID不为空
                # 构造请求URL
                url = f'https://ngdc.cncb.ac.cn/gwh/api/public/assembly/{id}'
                
                try:
                    # 发送GET请求
                    response = requests.get(url)
                    response.raise_for_status()  # 如果请求失败则抛出异常
                    
                    # 将JSON响应转为Python字典
                    response_json = response.json()
                    
                    # 解析JSON对象并转换为适合CSV格式的行
                    # 这里只是一个示例，具体字段需要根据返回的JSON内容调整
                    if not header_written:
                        # 写入表头
                        headers = response_json.keys()
                        csvwriter.writerow(['ID'] + list(headers))
                        header_written = True
                    
                    # 写入数据行
                    row = [id] + list(response_json.values())
                    csvwriter.writerow(row)
                    
                    print(f"ID: {id} 已经成功获取并写入CSV")
                except requests.exceptions.RequestException as e:
                    # 如果请求出错，记录错误信息到CSV中
                    csvwriter.writerow([id, f'请求失败: {str(e)}'])
                    print(f"ID: {id} 获取失败！")

print("任务完成，结果已保存到下载详情.csv")
