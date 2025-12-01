# NCBI Biosample & SRA XML 下载器

## 功能特点

### 🚀 核心功能
- **批量下载**: 根据SAMPLE编号批量获取Biosample和SRA的XML数据
- **并行处理**: 支持用户自定义并行任务数，提高下载效率
- **断点续跑**: 自动跳过已成功下载的文件，支持中断后继续
- **详细日志**: 记录每个样本的处理状态，便于追踪和重试

### 📁 输出结构
```
/mnt/c/Users/Administrator/Desktop/
├── biosample_xml/          # Biosample XML文件目录
│   ├── SAMN12345678.xml
│   └── SAMN87654321.xml
├── SRA_xml/                # SRA XML文件目录
│   ├── SRR12345678.xml
│   └── SRR87654321.xml
└── download_log.txt        # 详细处理日志
```

## 使用方法

### 📝 准备输入文件
创建包含SAMPLE编号的文本文件 `1.txt`：
```
SAMN21876385
SAMN21876334
SAMN03160862
SAMN03160858
```

### 🏃 运行脚本

#### 基本使用
```bash
# 使用默认并行数（3个任务）
./fetch_biosample_sra_robust.sh
```

#### 自定义并行数
```bash
# 使用5个并行任务（推荐网络较好时使用）
./fetch_biosample_sra_robust.sh 5

# 使用1个任务（单线程，最安全）
./fetch_biosample_sra_robust.sh 1

# 使用10个任务（网络很好时使用，可能触发API限制）
./fetch_biosample_sra_robust.sh 10
```

## 日志系统

### 📊 日志格式
日志文件 `download_log.txt` 记录每个样本的处理详情：
```
# Format: TIMESTAMP | SAMPLE_ID | STATUS | BIOSAMPLE_FILE | SRA_FILES | NOTES

2025-08-19 17:25:22 | SAMN21876385 | SUCCESS | /path/to/SAMN21876385.xml | SRR12345678,SRR87654321 | All files downloaded successfully
2025-08-19 17:25:25 | SAMN21876334 | BIOSAMPLE_FAILED | NOT_FOUND |  | Biosample not found
2025-08-19 17:25:28 | SAMN03160862 | SRA_FAILED | /path/to/SAMN03160862.xml | FAILED | SRA API error
```

### 🔄 状态说明
- **SUCCESS**: 样本完全处理成功
- **BIOSAMPLE_FAILED**: Biosample获取失败
- **SRA_FAILED**: SRA数据获取失败  
- **SKIPPED**: 已处理过，本次跳过

## 断点续跑功能

### ✨ 智能恢复
- 脚本会自动检查已完成的样本
- 重新运行时只处理未完成或失败的样本
- 无需手动清理或重复配置

### 🔧 失败重试
脚本完成后会自动生成失败样本列表：
```bash
# 查看失败的样本
cat retry_samples.txt

# 重新处理失败的样本
# （脚本会提示具体命令）
```

## 性能建议

### 🌐 并行数选择指南
| 网络状况 | 推荐并行数 | 说明 |
|---------|-----------|------|
| 🔥 网络很好 | 5-10 | 最大化利用带宽 |
| 👍 网络一般 | 3-5 | 平衡速度和稳定性 |
| ⚠️ 网络不稳定 | 1-3 | 确保稳定性优先 |
| 🧪 测试阶段 | 1 | 避免API限制 |

### ⚡ 优化技巧
1. **首次运行**: 建议使用较低并行数测试
2. **大批量数据**: 可以分批处理，利用断点续跑功能
3. **网络监控**: 如果频繁失败，降低并行数
4. **API限制**: 遇到限制时稍等片刻再重试

## 故障排除

### ❌ 常见问题
1. **API限制**: 降低并行数或稍后重试
2. **网络超时**: 检查网络连接，使用单线程模式
3. **文件权限**: 确保脚本有写入权限
4. **工具缺失**: 安装 NCBI E-utilities

### 🔧 安装依赖
```bash
# 使用conda安装
conda install -c bioconda entrez-direct

# 或使用官方安装脚本
sh -c "$(curl -fsSL ftp://ftp.ncbi.nlm.nih.gov/entrez/entrezdirect/install-edirect.sh)"
```

## 输出示例

### 📈 运行过程
```bash
开始处理SAMPLE编号...
输入文件：/mnt/c/Users/Administrator/Desktop/1.txt
日志文件：/mnt/c/Users/Administrator/Desktop/download_log.txt
并行任务数：5
================================
文件中共有 10 个有效样本
已完成样本数：3
需要处理样本数：7
================================

[1/10] 处理SAMPLE: SAMN21876385 (PID: 12345)
[2/10] 处理SAMPLE: SAMN21876334 (PID: 12346)
  [12345] ✓ 样本 SAMN21876385 已在之前成功处理，跳过
  [12346] 正在获取biosample XML...
  [12346] ✓ Biosample XML已保存
  [12346] 正在搜索关联的SRA数据...
  [12346] ✓ 找到SRA数据: SRR12345678
```

### 📊 完成统计
```bash
================================
所有SAMPLE处理完成！
统计信息：
- 成功获取的Biosample XML: 8 个
- 成功获取的SRA XML: 12 个

详细统计（基于日志文件）：
- 完全成功: 8 个
- Biosample失败: 1 个  
- SRA失败: 1 个
- 已跳过: 3 个

需要重新处理的失败样本：
SAMN21876334
SAMN03160862

失败样本已保存到: retry_samples.txt
```

## 版本信息
- **版本**: v2.0 (支持并行+断点续跑)
- **作者**: GitHub Copilot
- **日期**: 2025-08-19
- **兼容**: Linux/WSL环境
