# QKA文件合并工具使用说明

这个工具可以将多个 `.qka` 文件合并成一个文件，支持自动添加章节分隔符。

## 文件说明

1. **merge_qka_files.py** - 完整版命令行工具
2. **qka_merger_simple.py** - 简化版，可在代码中直接调用
3. **merge_example.py** - 使用示例

## 快速使用

### 方法1: 命令行使用

```bash
# 基本合并
python merge_qka_files.py file1.qka file2.qka file3.qka -o merged.qka

# 批量合并所有qka文件
python merge_qka_files.py *.qka -o all_merged.qka

# 不添加分隔符
python merge_qka_files.py *.qka -o merged.qka --no-separators
```


## 功能特点

- ✅ 自动合并多个qka文件的Steps
- ✅ 可选的章节分隔符
- ✅ 错误处理和日志输出
- ✅ 支持通配符批量处理
- ✅ 保持原始JSON结构
- ✅ UTF-8编码支持

## 参数说明

- `input_files`: 输入的qka文件路径列表
- `output_file`: 输出的合并文件路径  
- `add_separators`: 是否添加章节分隔符（默认True）

## 实际测试

已成功测试合并以下文件：
- tar命令_20251020_090246.qka
- gzip命令_20251020_090252.qka  
- gunzip命令_20251020_090258.qka
- bgzip命令_20251020_090304.qka

生成的合并文件包含所有命令，并按文件名自动分组。