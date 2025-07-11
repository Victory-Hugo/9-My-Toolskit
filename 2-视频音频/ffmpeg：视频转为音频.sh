#!/bin/bash
# 提示用户输入包含 mp4 文件的目录路径
read -p "请输入包含 mp4 文件的文件夹路径: " dir_path

# 检查目录是否存在
if [ ! -d "$dir_path" ]; then
    echo "错误：输入的路径不是一个有效的目录。"
    exit 1
fi

# 遍历目录下的所有文件
for file in "$dir_path"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        # 获取文件扩展名，并转换为小写
        ext="${filename##*.}"
        ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        # 获取不包含扩展名的文件名
        base="${filename%.*}"

        if [ "$ext_lower" = "mp4" ]; then
            output_file="$dir_path/${base}.mp3"
            
            # 判断输出文件是否已存在，若存在则跳过
            if [ -f "$output_file" ]; then
                echo "输出文件 $output_file 已存在，跳过转换。"
                continue
            fi

            echo "正在转换文件："
            echo "  输入文件: $file"
            echo "  输出文件: $output_file"

            # 使用 ffmpeg 提取音频并转换为 mp3 格式
            ffmpeg -i "$file" -q:a 0 -map a "$output_file"

            if [ $? -eq 0 ]; then
                echo "$file 转换成功！"
            else
                echo "转换文件 $file 时出错。"
            fi
            echo "-------------------------------"
        fi
    fi
done

echo "MP4转MP3处理完成。"
