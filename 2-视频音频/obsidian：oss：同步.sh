# --delete：OSS 上多余的文件将被删除，与本地保持一致。
# --update（-u）：仅同步目标端不存在或源文件比目标端更新的文件。
# --jobs 10：并发 10 个任务，加快传输速度（根据你的带宽和 OSS 限制酌情调整）。
# --checkpoint-dir：指定断点续传信息存储目录，遇大文件或网络波动可自动续传。

ossutil sync \
    /mnt/f/D1_Obsidian_publish/ \
    oss://obsidian-publisher/D1_Obsidian_publish/ \
    --delete \
    --update \
    --job 20
# # 1.基本同步命令
# # *功能说明：该命令会将本地文件夹中的内容同步到 OSS，仅传输有变动的文件（基于文件修改时间和大小判断）
# ossutil sync \
#     /mnt/f/D1_Obsidian_publish/ \
#     oss://obsidian-publisher/D1_Obsidian_publish/

# # 2.同步时删除多余文件
# # *如果希望删除 OSS 中已存在但本地不存在的文件，可使用 --delete 参数：
# # *注意事项：启用 --delete 参数后，OSS 中多余的文件将被删除，建议开启版本控制以防止误删重要数据
# ossutil rm --force oss://picturerealm/obsidian/20240616211548.png
# ossutil sync \
#     /mnt/f/D1_Obsidian_publish/ \
#     oss://obsidian-publisher/D1_Obsidian_publish/ --delete

# # 3. 过滤特定文件类型
# # 如果仅同步特定类型的文件，可使用 --include 或 --exclude 参数：
# # 仅同步 .md 文件
# ossutil sync \
#     /mnt/f/D1_Obsidian_publish/ \
#     oss://obsidian-publisher/D1_Obsidian_publish/ --include "*.md"

# # 排除 .tmp 文件
# ossutil sync \
#     /mnt/f/D1_Obsidian_publish/ \
#     oss://obsidian-publisher/D1_Obsidian_publish/ --exclude "*.tmp"
# # 4. 增量同步
# # 通过 -u/--update 参数实现增量同步，仅同步满足以下条件的文件：

# # 目标端不存在该文件。
# # 源文件比目标文件更新。
# ossutil sync \
#     /mnt/f/D1_Obsidian_publish/ \
#     oss://obsidian-publisher/D1_Obsidian_publish/ -u

# # 四、定时同步任务
# # 1. Linux 系统
# # 使用 crontab 配置定时任务：
# # 编辑定时任务：
# crontab -e
# # 添加如下内容，每天凌晨 2 点执行同步：
# 0 2 * * * ossutil sync \
#     /mnt/f/D1_Obsidian_publish/ \
#     oss://obsidian-publisher/D1_Obsidian_publish/ --delete


# # 2. Windows 系统
# # sync_to_oss.bat，内容如下：
# cd /d "C:\ossutil"
# ossutil sync D:\mnt\f\D1_Obsidian_publish \
#     oss://obsidian-publisher/D1_Obsidian_publish/ --delete

# # 五、注意事项
# # 文件数量限制
# # 如果使用 --delete 参数，单次同步最多支持 100 万个文件，超出需分批处理
# # 断点续传
# # 默认情况下，ossutil 支持断点续传，可通过 --checkpoint-dir 参数指定断点续传信息的存储目录。
# # 调整并发任务数：使用 --jobs 参数提高同步效率。例如：
# ossutil sync \
#     /mnt/f/D1_Obsidian_publish/ \
#     oss://obsidian-publisher/D1_Obsidian_publish/ --jobs 10
# # 设置最大下载速度：使用 --maxdownspeed 参数限制带宽占用。
