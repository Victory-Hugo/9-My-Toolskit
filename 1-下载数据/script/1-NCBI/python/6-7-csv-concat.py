#!/usr/bin/env python3
import sys
import os
import pandas as pd
import glob

def concat_csvs(input_dir, output_file):
    # 获取目录下所有 CSV 文件
    csv_files = glob.glob(os.path.join(input_dir, "*.csv"))
    if not csv_files:
        print(f"错误: 在目录 {input_dir} 下没有找到 CSV 文件")
        sys.exit(1)

    dfs = []
    for f in csv_files:
        try:
            df = pd.read_csv(f, dtype=str)  # 全部读为字符串，避免类型冲突
            dfs.append(df)
        except Exception as e:
            print(f"警告: 读取 {f} 出错: {e}")

    # 合并，保留所有列
    merged_df = pd.concat(dfs, axis=0, join="outer").fillna("NA")

    # 保存
    merged_df.to_csv(output_file, index=False)
    print(f"合并完成: {output_file} (共 {len(merged_df)} 行, {len(merged_df.columns)} 列)")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"用法: {sys.argv[0]} input_csv_dir output_csv_file")
        sys.exit(1)

    input_dir = sys.argv[1]
    output_file = sys.argv[2]

    if not os.path.isdir(input_dir):
        print(f"错误: 输入目录不存在: {input_dir}")
        sys.exit(1)

    concat_csvs(input_dir, output_file)
