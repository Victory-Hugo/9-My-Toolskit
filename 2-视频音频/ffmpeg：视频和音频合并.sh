#!/bin/bash
# 提示用户输入包含 mp4 和 m4a 文件的目录路径
read -p "请输入包含 mp4 和 m4a 文件的文件夹路径: " dir_path

# 检查目录是否存在
if [ ! -d "$dir_path" ]; then
    echo "错误：输入的路径不是一个有效的目录。"
    exit 1
fi

# 使用关联数组存储前缀对应的文件（要求 Bash 4 及以上版本）
declare -A mp4_files
declare -A m4a_files

# 遍历目录下的所有文件
for file in "$dir_path"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        # 获取文件扩展名，并转换为小写
        ext="${filename##*.}"
        ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        # 获取不包含扩展名的文件名
        base="${filename%.*}"
        # 按第一个 '-' 分割，取其之前的部分作为前缀
        if [[ "$base" == *"-"* ]]; then
            prefix="${base%%-*}"
        else
            prefix="$base"
        fi

        if [ "$ext_lower" = "mp4" ]; then
            mp4_files["$prefix"]="$file"
        elif [ "$ext_lower" = "m4a" ]; then
            m4a_files["$prefix"]="$file"
        fi
    fi
done

# 对于同时存在 mp4 和 m4a 文件的前缀，依次合并
found_match=false
for prefix in "${!mp4_files[@]}"; do
    if [ -n "${m4a_files[$prefix]}" ]; then
        video_file="${mp4_files[$prefix]}"
        audio_file="${m4a_files[$prefix]}"
        output_file="$dir_path/${prefix}_合并.mp4"

        # 判断输出文件是否已存在，若存在则跳过
        if [ -f "$output_file" ]; then
            echo "输出文件 $output_file 已存在，跳过合并。"
            continue
        fi

        echo "正在合并文件："
        echo "  视频文件: $video_file"
        echo "  音频文件: $audio_file"
        echo "  输出文件: $output_file"

        # 使用 ffmpeg 直接复制视频和音频流，保证无损
        ffmpeg -i "$video_file" -i "$audio_file" -c:v copy -c:a copy -map 0:v:0 -map 1:a:0 "$output_file"

        if [ $? -eq 0 ]; then
            echo "$prefix 合并成功！"
        else
            echo "合并前缀为 $prefix 的文件时出错。"
        fi
        echo "-------------------------------"
        found_match=true
    fi
done

if [ "$found_match" = false ]; then
    echo "未找到匹配的 mp4 和 m4a 文件。"
fi
