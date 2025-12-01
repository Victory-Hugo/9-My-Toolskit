import pandas as pd
import sys

# 从命令行获取传入的文件路径参数
input_file = sys.argv[1]  # 输入文件路径
output_file = sys.argv[2]  # 输出文件路径

# 加载CSV文件
df = pd.read_csv(input_file)

# 提取需要的列: BioSample, Run 和 SampleName
df_filtered = df[['BioSample', 'Run', 'SampleName']]

# 对每个 BioSample 合并多个 Run 值（如果有多个 Run 对应同一个 BioSample），
# 只保留每个 BioSample 对应的唯一 SampleName
df_grouped = df_filtered.groupby('BioSample').agg({
    'Run': lambda x: ';'.join(x),   # 合并多个 Run 值
    'SampleName': 'first'            # 由于 BioSample 和 SampleName 是一对一关系，保留第一个 SampleName
}).reset_index()

# 保存为新的CSV文件
df_grouped.to_csv(output_file, sep='\t', index=False, header=False)

print(f"文件已保存为 {output_file}")
