#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import argparse
import pandas as pd

def parse_args():
    parser = argparse.ArgumentParser(
        description="对比本地与云端 FASTQ 的 MD5，输出四类结果并检查必要字段"
    )
    parser.add_argument(
        "--local-file", "-l", required=True,
        help="本地 md5 文件，格式：md5  File_Path，以空白分隔"
    )
    parser.add_argument(
        "--cloud-file", "-c", required=True,
        help="云端 md5 文件，TSV 格式，包含 run_accession, fastq_md5, fastq_ftp 等列"
    )
    parser.add_argument(
        "--outdir", "-o", required=True,
        help="输出目录，结果文件将写入此目录"
    )
    return parser.parse_args()

def check_columns(df, name, required_cols):
    """检查 df 是否包含所有 required_cols，缺失则报错并退出"""
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        print(f"ERROR: 在 `{name}` 中缺少必要字段: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)

def main():
    args = parse_args()
    LOCAL_FILE = args.local_file
    CLOUD_FILE = args.cloud_file
    OUTDIR = args.outdir.rstrip("/") + "/"

    # 确保输出目录存在
    os.makedirs(OUTDIR, exist_ok=True)
    print(f"输出目录: {OUTDIR}")

    # 1. 读取本地 md5
    print(f"读取本地文件: {LOCAL_FILE}")
    try:
        df_local = pd.read_csv(
            LOCAL_FILE, sep="\s+", header=None,
            names=["md5", "File_Path"], engine="python"
        )
    except Exception as e:
        print(f"ERROR: 无法读取本地文件 `{LOCAL_FILE}`：{e}", file=sys.stderr)
        sys.exit(1)

    check_columns(df_local, "本地文件", ["md5", "File_Path"])
    df_local["File_Name"] = (
        df_local["File_Path"]
        .str.split("/")
        .str[-1]
        .str.replace(".fastq.gz", "", regex=False)
    )
    df_local = df_local[["File_Name", "md5"]].drop_duplicates()
    print(f"本地记录数（去重后）: {len(df_local)}")

    # 2. 读取云端 md5
    print(f"读取云端文件: {CLOUD_FILE}")
    try:
        df_cloud = pd.read_csv(CLOUD_FILE, sep="\t", engine="python")
    except Exception as e:
        print(f"ERROR: 无法读取云端文件 `{CLOUD_FILE}`：{e}", file=sys.stderr)
        sys.exit(1)

    check_columns(df_cloud, "云端文件", ["run_accession", "fastq_md5", "fastq_ftp"])
    df_cloud = df_cloud.rename(
        columns={"run_accession": "File_Name", "fastq_md5": "md5"}
    )

    # 拆分双端测序
    df_cloud["fastq_ftp_new"] = df_cloud["fastq_ftp"].str.split(";")
    df_cloud["md5_new"]       = df_cloud["md5"].str.split(";")
    df_long = df_cloud.explode(["fastq_ftp_new", "md5_new"], ignore_index=True)

    df_cloud_new = pd.DataFrame({
        "File_Name": (
            df_long["fastq_ftp_new"]
            .str.split("/")
            .str[-1]
            .str.replace(".fastq.gz", "", regex=False)
        ),
        "md5_new": df_long["md5_new"]
    }).drop_duplicates()
    print(f"云端记录数（拆分展开后去重）: {len(df_cloud_new)}")

    # 3. 标注来源 & 合并对比
    df_local["Type"]       = "Local"
    df_cloud_new["Type"]   = "Cloud"

    df_merge = pd.merge(
        df_cloud_new, df_local,
        on="File_Name", how="outer",
        suffixes=("_cloud", "_local")
    )

    mask_both          = df_merge["md5_new"].notnull() & df_merge["md5"].notnull()
    mask_equal         = mask_both & (df_merge["md5_new"] == df_merge["md5"])
    mask_not_equal     = mask_both & (df_merge["md5_new"] != df_merge["md5"])
    mask_only_cloud    = df_merge["md5_new"].notnull() & df_merge["md5"].isnull()

    df_match     = df_merge[mask_equal]
    df_mismatch  = df_merge[mask_not_equal]
    df_need      = df_merge[mask_only_cloud]

    print(f"MD5 完全匹配: {len(df_match)} 条")
    print(f"MD5 不匹配: {len(df_mismatch)} 条")
    # print(f"本地缺失需下载: {len(df_need)} 条")

    # 4. 提取前缀并写文件
    def extract_prefix(df):
        return pd.Series(df["File_Name"].str.split("_").str[0].unique()).sort_values()

    # —— 修改部分：md5_完全匹配 输出两列（前缀 + 正确 md5）
    df_match_prefix = df_match.copy()
    df_match_prefix["Prefix"] = df_match_prefix["File_Name"].str.split("_").str[0]
    # 取每个 Prefix 对应的第一个 md5 —— 保证 Prefix 数量不变
    df_match_prefix = (
        df_match_prefix[["Prefix", "md5"]]
        .drop_duplicates(subset=["Prefix"])
        .sort_values("Prefix")
    )
    df_match_prefix.to_csv(
        OUTDIR + "md5_完全匹配.txt",
        sep="\t", index=False, header=False
    )

    # 其余文件保持原样
    extract_prefix(df_mismatch).to_csv(
        OUTDIR + "md5_损坏.txt", sep="\t", index=False, header=False
    )
    # extract_prefix(df_need).to_csv(
    #     OUTDIR + "md5_缺失.txt", sep="\t", index=False, header=False
    # )
    # 损坏或缺失合并
    s1 = extract_prefix(df_mismatch)
    s2 = extract_prefix(df_need)
    # pd.concat([s1, s2], ignore_index=True) \
    #   .drop_duplicates() \
    #   .sort_values() \
    #   .to_csv(
    #       OUTDIR + "md5_损坏或缺失.txt",
    #       sep="\t", index=False, header=False
    #   )

    print("处理完成，输出文件：")
    print("  - md5_完全匹配.txt      （前缀 + 正确 md5）")
    print("  - md5_损坏.txt")
    # print("  - md5_缺失.txt")
    # print("  - md5_损坏或缺失.txt")

if __name__ == "__main__":
    main()
