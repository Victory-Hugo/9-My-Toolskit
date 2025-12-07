#!/usr/bin/env python3
"""
NCBI数据解压和整理模块

功能说明：
1. 自动解压ZIP文件到单独文件夹
2. 重命名和整理文件结构
3. 创建树状目录结构避免文件夹过多

支持模块导入和命令行调用两种方式。
"""

import argparse
import shutil
import sys
import zipfile
from pathlib import Path
from typing import Tuple
import logging
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import multiprocessing


def setup_logging(verbose: bool = False) -> None:
    """设置日志"""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%H:%M:%S'
    )


def extract_single_zip(zip_file: Path, root_dir: Path, overwrite: bool = False, backup: bool = False) -> Tuple[bool, str]:
    """
    解压单个ZIP文件
    
    Args:
        zip_file: ZIP文件路径
        root_dir: 根目录路径
        overwrite: 是否覆盖已存在的文件
        backup: 是否备份已存在的文件
        
    Returns:
        (是否成功, 消息)
    """
    try:
        # 确定解压目录名
        if zip_file.name.endswith('_downloaded.zip'):
            basename = zip_file.stem.replace('_downloaded', '')
        else:
            basename = zip_file.stem
            
        extract_dir = root_dir / basename
        
        # 检查目录是否已存在
        if extract_dir.exists():
            if overwrite:
                shutil.rmtree(extract_dir)
                message = f"覆盖: {basename}"
            elif backup:
                backup_name = f"{basename}.bak.{int(datetime.now().timestamp())}"
                backup_dir = root_dir / backup_name
                extract_dir.rename(backup_dir)
                message = f"备份并解压: {basename}"
            else:
                return False, f"跳过已存在: {basename}"
        else:
            message = f"解压: {basename}"
        
        # 解压文件
        extract_dir.mkdir(exist_ok=True)
        
        with zipfile.ZipFile(zip_file, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
        
        # 删除原ZIP文件以节省空间
        zip_file.unlink()
        
        return True, message
        
    except Exception as e:
        return False, f"解压 {zip_file.name} 失败: {e}"


def extract_zip_files(root_dir: Path, overwrite: bool = False, backup: bool = False, 
                     max_workers: int = None) -> Tuple[int, int]:
    """
    解压ZIP文件（并行处理）
    
    Args:
        root_dir: 根目录路径
        overwrite: 是否覆盖已存在的文件
        backup: 是否备份已存在的文件
        max_workers: 最大并发数（默认为CPU核心数）
        
    Returns:
        (总ZIP文件数, 成功解压数)
    """
    logging.info("步骤1: 解压ZIP文件...")
    
    if max_workers is None:
        max_workers = min(multiprocessing.cpu_count(), 8)  # 限制最大8个线程避免过度并发
    
    # 查找所有ZIP文件
    zip_patterns = ["*.zip", "*_downloaded.zip"]
    zip_files = []
    
    for pattern in zip_patterns:
        zip_files.extend(root_dir.glob(pattern))
    
    # 去重（可能有重复匹配）
    zip_files = list(set(zip_files))
    
    if not zip_files:
        logging.info("没有找到ZIP文件，跳过解压步骤")
        return 0, 0
    
    logging.info(f"找到 {len(zip_files)} 个ZIP文件，使用 {max_workers} 个线程并行处理")
    
    extracted_count = 0
    completed_count = 0
    
    # 使用线程池并行处理
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # 提交所有任务
        future_to_zip = {
            executor.submit(extract_single_zip, zip_file, root_dir, overwrite, backup): zip_file
            for zip_file in zip_files
        }
        
        # 处理完成的任务
        for future in as_completed(future_to_zip):
            zip_file = future_to_zip[future]
            completed_count += 1
            
            try:
                success, message = future.result()
                if success:
                    extracted_count += 1
                    logging.debug(message)
                else:
                    logging.warning(message)
                    
                # 每100个或每10%显示进度
                if completed_count % 100 == 0 or completed_count % max(len(zip_files) // 10, 1) == 0:
                    progress = completed_count / len(zip_files) * 100
                    logging.info(f"进度: {completed_count}/{len(zip_files)} ({progress:.1f}%) - 成功: {extracted_count}")
                    
            except Exception as e:
                logging.error(f"处理 {zip_file.name} 时发生未知错误: {e}")
    
    logging.info(f"解压完成: 共处理 {len(zip_files)} 个ZIP文件，成功解压 {extracted_count} 个")
    return len(zip_files), extracted_count


def rename_downloaded_dirs(root_dir: Path) -> int:
    """重命名 *_downloaded 目录"""
    logging.info("步骤2: 重命名 *_downloaded 目录...")
    
    count = 0
    for dir_path in root_dir.glob("*_downloaded"):
        if dir_path.is_dir():
            new_name = dir_path.name.replace("_downloaded", "")
            new_path = root_dir / new_name
            
            if not new_path.exists():
                dir_path.rename(new_path)
                count += 1
                logging.debug(f"重命名: {dir_path.name} -> {new_name}")
            else:
                logging.warning(f"目标目录已存在，跳过重命名: {dir_path.name}")
    
    logging.info(f"重命名完成: {count} 个目录")
    return count


def remove_useless_files(root_dir: Path) -> int:
    """删除无用文件"""
    logging.info("步骤3: 删除无用文件...")
    
    useless_patterns = ["README.md", "md5sum.txt", "assembly_data_report.jsonl", "dataset_catalog.json"]
    count = 0
    
    for pattern in useless_patterns:
        for file_path in root_dir.rglob(pattern):
            try:
                file_path.unlink()
                count += 1
                logging.debug(f"删除: {file_path}")
            except Exception as e:
                logging.warning(f"删除文件失败 {file_path}: {e}")
    
    logging.info(f"删除无用文件完成: {count} 个文件")
    return count


def rename_with_policy(src: Path, dst: Path, overwrite: bool, backup: bool) -> bool:
    """
    根据策略重命名文件
    
    Returns:
        True if renamed successfully, False otherwise
    """
    if dst.exists():
        if overwrite:
            logging.debug(f"覆盖: {src} -> {dst}")
            dst.unlink()
        elif backup:
            backup_name = f"{dst}.bak.{int(datetime.now().timestamp())}"
            logging.debug(f"备份: {dst} -> {backup_name}")
            dst.rename(Path(backup_name))
        else:
            logging.debug(f"跳过（目标已存在）: {src} -> {dst}")
            return False
    
    try:
        src.rename(dst)
        return True
    except Exception as e:
        logging.error(f"重命名失败 {src} -> {dst}: {e}")
        return False


def rename_biological_files(root_dir: Path, overwrite: bool = False, backup: bool = False) -> Tuple[int, int, int, int]:
    """
    重命名生物学文件
    
    Returns:
        (CDS文件数, GFF文件数, FASTA文件数, 蛋白质文件数)
    """
    cds_count = gff_count = fasta_count = protein_count = 0
    
    # 重命名CDS文件
    logging.info("步骤4: 重命名CDS文件...")
    for file_path in root_dir.rglob("cds_from_genomic.fna"):
        parent_name = file_path.parent.name
        new_path = file_path.parent / f"{parent_name}_CDS.fna"
        if rename_with_policy(file_path, new_path, overwrite, backup):
            cds_count += 1
    
    # 重命名GFF文件
    logging.info("步骤5: 重命名GFF文件...")
    for file_path in root_dir.rglob("genomic.gff"):
        parent_name = file_path.parent.name
        new_path = file_path.parent / f"{parent_name}.gff"
        if rename_with_policy(file_path, new_path, overwrite, backup):
            gff_count += 1
    
    # 重命名FASTA文件（排除CDS文件）
    logging.info("步骤6: 重命名FASTA文件...")
    for file_path in root_dir.rglob("*.fna"):
        if "_CDS.fna" not in file_path.name:
            parent_name = file_path.parent.name
            new_path = file_path.parent / f"{parent_name}.fasta"
            if rename_with_policy(file_path, new_path, overwrite, backup):
                fasta_count += 1
    
    # 重命名蛋白质文件
    logging.info("步骤7: 重命名蛋白质文件...")
    for file_path in root_dir.rglob("protein.faa"):
        parent_name = file_path.parent.name
        new_path = file_path.parent / f"{parent_name}.faa"
        if rename_with_policy(file_path, new_path, overwrite, backup):
            protein_count += 1
    
    return cds_count, gff_count, fasta_count, protein_count


def flatten_ncbi_structure(root_dir: Path) -> int:
    """展开NCBI数据集目录结构"""
    logging.info("步骤8: 展开NCBI数据集目录结构...")
    
    count = 0
    for sample_dir in root_dir.iterdir():
        if not sample_dir.is_dir():
            continue
            
        data_base = sample_dir / "ncbi_dataset" / "data"
        if not data_base.exists():
            continue
        
        logging.debug(f"处理样本目录: {sample_dir.name}")
        
        for inner_dir in data_base.iterdir():
            if not inner_dir.is_dir():
                continue
                
            # 移动内部文件到样本目录
            for item in inner_dir.iterdir():
                dest = sample_dir / item.name
                
                # 如果目标存在，跳过
                if dest.exists():
                    logging.warning(f"目标文件已存在，跳过: {dest}")
                    continue
                    
                try:
                    shutil.move(str(item), str(dest))
                    count += 1
                except Exception as e:
                    logging.error(f"移动文件失败 {item} -> {dest}: {e}")
            
            # 尝试删除空目录
            try:
                inner_dir.rmdir()
            except OSError:
                logging.debug(f"保留非空目录: {inner_dir}")
        
        # 尝试删除上级目录
        try:
            data_base.rmdir()
            (sample_dir / "ncbi_dataset").rmdir()
        except OSError:
            logging.debug(f"保留非空目录结构: {sample_dir / 'ncbi_dataset'}")
    
    logging.info(f"展开目录结构完成: 移动 {count} 个文件")
    return count


def create_tree_structure(root_dir: Path, max_files_per_dir: int = 5000) -> bool:
    """创建树状目录结构"""
    logging.info("步骤9: 创建树状目录结构...")
    
    # 获取所有需要整理的目录
    dirs_to_organize = [d for d in root_dir.iterdir() 
                       if d.is_dir() and "_organized_" not in d.name and "_backup_" not in d.name]
    
    total_dirs = len(dirs_to_organize)
    logging.info(f"需要整理的目录总数: {total_dirs}")
    
    if total_dirs == 0:
        logging.info("没有需要整理的目录。")
        return False
    
    if total_dirs <= max_files_per_dir:
        logging.info("目录数量未超过限制，无需重新组织")
        return False
    
    # 创建临时目录
    timestamp = int(datetime.now().timestamp())
    temp_organized = root_dir.parent / f"{root_dir.name}_organized_{timestamp}"
    temp_organized.mkdir()
    
    logging.info("目录数量超过限制，创建分层结构")
    
    try:
        # 整理目录到分层结构
        for i, dir_path in enumerate(dirs_to_organize):
            # 计算嵌套路径
            level1 = i // max_files_per_dir
            nested_dir_name = f"{level1 * max_files_per_dir:04d}-{(level1 + 1) * max_files_per_dir - 1:04d}"
            target_dir = temp_organized / nested_dir_name
            
            # 创建目标目录
            target_dir.mkdir(exist_ok=True)
            
            # 移动目录
            shutil.move(str(dir_path), str(target_dir))
            
            # 显示进度
            if (i + 1) % 1000 == 0 or (i + 1) == total_dirs:
                logging.info(f"已整理: {i + 1}/{total_dirs}")
        
        # 备份原目录并替换
        backup_dir = root_dir.parent / f"{root_dir.name}_backup_{timestamp}"
        logging.info(f"备份原目录到: {backup_dir}")
        root_dir.rename(backup_dir)
        temp_organized.rename(root_dir)
        
        # 统计新结构
        level1_dirs = len([d for d in root_dir.iterdir() if d.is_dir()])
        level2_dirs = sum(len([d for d in subdir.iterdir() if d.is_dir()]) 
                         for subdir in root_dir.iterdir() if subdir.is_dir())
        
        logging.info("树状结构创建完成！")
        logging.info(f"原目录备份: {backup_dir}")
        logging.info(f"新目录结构: {root_dir}")
        logging.info("新目录结构统计:")
        logging.info(f"  一级目录数: {level1_dirs}")
        logging.info(f"  二级目录数: {level2_dirs}")
        
        return True
        
    except Exception as e:
        logging.error(f"创建树状结构失败: {e}")
        # 清理临时目录
        if temp_organized.exists():
            shutil.rmtree(temp_organized)
        return False


def run(root_directory: str, 
        overwrite: bool = False, 
        backup: bool = False, 
        max_files_per_dir: int = 5000,
        max_workers: int = None,
        verbose: bool = False) -> dict:
    """
    执行完整的解压和整理流程
    
    Args:
        root_directory: 根目录路径
        overwrite: 是否覆盖已存在的文件
        backup: 是否备份已存在的文件
        max_files_per_dir: 每个目录最大文件数
        max_workers: 最大并发数（默认为CPU核心数）
        verbose: 是否显示详细日志
        
    Returns:
        包含处理结果统计的字典
    """
    setup_logging(verbose)
    
    root_dir = Path(root_directory)
    if not root_dir.exists():
        raise ValueError(f"目录不存在: {root_directory}")
    if not root_dir.is_dir():
        raise ValueError(f"路径不是目录: {root_directory}")
    
    if max_workers is None:
        max_workers = min(multiprocessing.cpu_count(), 8)
    
    logging.info(f"开始处理目录: {root_dir}")
    logging.info(f"每目录最大文件数: {max_files_per_dir}")
    logging.info(f"并发线程数: {max_workers}")
    
    results = {}
    
    try:
        # 1. 解压ZIP文件（并行）
        zip_total, zip_extracted = extract_zip_files(root_dir, overwrite, backup, max_workers)
        results['zip_files'] = {'total': zip_total, 'extracted': zip_extracted}
        
        # 2. 重命名目录
        renamed_dirs = rename_downloaded_dirs(root_dir)
        results['renamed_dirs'] = renamed_dirs
        
        # 3. 删除无用文件
        deleted_files = remove_useless_files(root_dir)
        results['deleted_files'] = deleted_files
        
        # 4-7. 重命名生物学文件
        cds_count, gff_count, fasta_count, protein_count = rename_biological_files(
            root_dir, overwrite, backup)
        results['renamed_files'] = {
            'cds': cds_count,
            'gff': gff_count, 
            'fasta': fasta_count,
            'protein': protein_count
        }
        
        # 8. 展开目录结构
        moved_files = flatten_ncbi_structure(root_dir)
        results['moved_files'] = moved_files
        
        # 9. 创建树状结构
        tree_created = create_tree_structure(root_dir, max_files_per_dir)
        results['tree_created'] = tree_created
        
        logging.info("全部完成！")
        return results
        
    except Exception as e:
        logging.error(f"处理过程中发生错误: {e}")
        raise


def main():
    """命令行入口函数"""
    parser = argparse.ArgumentParser(
        description="NCBI数据解压和整理工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例用法:
  %(prog)s /path/to/download
  %(prog)s /path/to/download --overwrite --max-files 3000
  %(prog)s /path/to/download --backup --verbose --max-workers 4
  %(prog)s /path/to/download -j 16 -v  # 使用16个线程并显示详细日志
        """
    )
    
    parser.add_argument(
        "root_directory",
        help="下载目录路径"
    )
    
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="覆盖已存在的文件"
    )
    
    parser.add_argument(
        "--backup", 
        action="store_true",
        help="备份已存在的文件"
    )
    
    parser.add_argument(
        "--max-files",
        type=int,
        default=5000,
        help="每个目录最大文件数 (默认: 5000)"
    )
    
    parser.add_argument(
        "--max-workers", "-j",
        type=int,
        help="最大并发线程数 (默认: CPU核心数，最大8)"
    )
    
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="显示详细日志"
    )
    
    args = parser.parse_args()
    
    try:
        results = run(
            root_directory=args.root_directory,
            overwrite=args.overwrite,
            backup=args.backup,
            max_files_per_dir=args.max_files,
            max_workers=args.max_workers,
            verbose=args.verbose
        )
        
        # 输出结果摘要
        print("\n" + "="*50)
        print("处理结果摘要:")
        print(f"ZIP文件: {results['zip_files']['extracted']}/{results['zip_files']['total']} 个解压成功")
        print(f"重命名目录: {results['renamed_dirs']} 个")
        print(f"删除无用文件: {results['deleted_files']} 个")
        print(f"重命名文件: CDS({results['renamed_files']['cds']}) GFF({results['renamed_files']['gff']}) "
              f"FASTA({results['renamed_files']['fasta']}) 蛋白质({results['renamed_files']['protein']})")
        print(f"移动文件: {results['moved_files']} 个")
        print(f"创建树状结构: {'是' if results['tree_created'] else '否'}")
        print("="*50)
        
    except Exception as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()