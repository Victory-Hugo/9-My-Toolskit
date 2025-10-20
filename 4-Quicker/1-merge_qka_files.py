#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QKA文件合并工具
用于将多个 .qka 文件合并成一个文件
"""

import json
import os
import sys
from typing import List, Dict, Any
import argparse


def load_qka_file(file_path: str) -> Dict[str, Any]:
    """加载qka文件并返回JSON对象"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read().strip()
            if not content:
                print(f"警告: 文件 {file_path} 是空的，跳过")
                return None
            return json.loads(content)
    except FileNotFoundError:
        print(f"错误: 文件 {file_path} 不存在")
        return None
    except json.JSONDecodeError as e:
        print(f"错误: 文件 {file_path} JSON格式错误: {e}")
        return None
    except Exception as e:
        print(f"错误: 读取文件 {file_path} 时发生错误: {e}")
        return None


def create_section_separator(title: str) -> List[Dict[str, Any]]:
    """创建章节分隔符"""
    return [
        {
            "StepRunnerKey": "sys:outputText",
            "InputParams": {
                "content": {
                    "VarKey": None,
                    "Value": f"# ========== {title.upper()} =========="
                },
                "method": {
                    "VarKey": None,
                    "Value": "input"
                },
                "appendReturn": {
                    "VarKey": None,
                    "Value": "0"
                }
            },
            "OutputParams": {},
            "IfSteps": None,
            "ElseSteps": None,
            "Note": None,
            "Disabled": False,
            "Collapsed": False,
            "DelayMs": 0
        },
        {
            "StepRunnerKey": "sys:keyInput",
            "InputParams": {
                "keys": {
                    "VarKey": None,
                    "Value": "{\"CtrlKeys\":[],\"Keys\":[13]}"
                }
            },
            "OutputParams": {},
            "IfSteps": None,
            "ElseSteps": None,
            "Note": None,
            "Disabled": False,
            "Collapsed": False,
            "DelayMs": 0
        }
    ]


def merge_qka_files(input_files: List[str], output_file: str, add_separators: bool = True) -> bool:
    """
    合并多个qka文件
    
    Args:
        input_files: 输入的qka文件路径列表
        output_file: 输出的合并文件路径
        add_separators: 是否添加章节分隔符
    
    Returns:
        bool: 是否成功合并
    """
    
    # 基础模板
    merged_data = {
        "LimitSingleInstance": True,
        "SummaryExpression": "$$",
        "SubPrograms": [],
        "Variables": [],
        "Steps": []
    }
    
    successful_files = []
    
    for i, file_path in enumerate(input_files):
        print(f"正在处理文件 {i+1}/{len(input_files)}: {file_path}")
        
        # 加载qka文件
        qka_data = load_qka_file(file_path)
        if qka_data is None:
            continue
            
        # 提取文件名作为章节标题
        file_name = os.path.splitext(os.path.basename(file_path))[0]
        
        # 添加章节分隔符（如果启用且不是第一个文件）
        if add_separators and (merged_data["Steps"] or successful_files):
            separator_steps = create_section_separator(file_name)
            merged_data["Steps"].extend(separator_steps)
        
        # 合并Steps
        if "Steps" in qka_data and isinstance(qka_data["Steps"], list):
            merged_data["Steps"].extend(qka_data["Steps"])
            successful_files.append(file_path)
            print(f"  ✓ 成功添加 {len(qka_data['Steps'])} 个步骤")
        else:
            print(f"  ⚠ 文件中没有找到有效的Steps")
        
        # 合并其他字段（如Variables, SubPrograms等，如果需要的话）
        if "Variables" in qka_data and isinstance(qka_data["Variables"], list):
            merged_data["Variables"].extend(qka_data["Variables"])
        
        if "SubPrograms" in qka_data and isinstance(qka_data["SubPrograms"], list):
            merged_data["SubPrograms"].extend(qka_data["SubPrograms"])
    
    if not successful_files:
        print("错误: 没有成功处理任何文件")
        return False
    
    # 保存合并后的文件
    try:
        # 确保输出目录存在
        output_dir = os.path.dirname(output_file)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(merged_data, f, ensure_ascii=False, indent=2)
        
        print(f"\n✅ 成功合并 {len(successful_files)} 个文件到: {output_file}")
        print(f"总共包含 {len(merged_data['Steps'])} 个步骤")
        
        return True
        
    except Exception as e:
        print(f"错误: 保存合并文件时发生错误: {e}")
        return False


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='合并多个QKA文件')
    parser.add_argument('input_files', nargs='+', help='输入的qka文件路径')
    parser.add_argument('-o', '--output', required=True, help='输出的合并文件路径')
    parser.add_argument('--no-separators', action='store_true', help='不添加章节分隔符')
    
    args = parser.parse_args()
    
    print("QKA文件合并工具")
    print("=" * 50)
    
    # 验证输入文件
    valid_files = []
    for file_path in args.input_files:
        if os.path.exists(file_path):
            valid_files.append(file_path)
        else:
            print(f"警告: 文件不存在，跳过: {file_path}")
    
    if not valid_files:
        print("错误: 没有找到有效的输入文件")
        sys.exit(1)
    
    # 执行合并
    success = merge_qka_files(
        valid_files, 
        args.output, 
        add_separators=not args.no_separators
    )
    
    if success:
        print("\n🎉 合并完成！")
        sys.exit(0)
    else:
        print("\n❌ 合并失败！")
        sys.exit(1)


def example_usage():
    """示例用法"""
    print("\n示例用法:")
    print("1. 基本合并:")
    print("   python merge_qka_files.py file1.qka file2.qka file3.qka -o merged.qka")
    print("\n2. 不添加分隔符:")
    print("   python merge_qka_files.py *.qka -o merged.qka --no-separators")
    print("\n3. 使用通配符:")
    print("   python merge_qka_files.py /path/to/*.qka -o /output/merged.qka")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        print("QKA文件合并工具")
        print("用法: python merge_qka_files.py [输入文件...] -o [输出文件]")
        example_usage()
        sys.exit(0)
    
    main()