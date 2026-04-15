#!/usr/bin/env bash

# 读取简单 YAML 子集：
# - 顶层 section
# - section 下二级 key: value
# - 两空格缩进
# 解析后导出变量名为 section_key，例如 project_base_dir

load_yaml_config() {
    local config_file="$1"

    if [[ -z "${config_file}" ]]; then
        echo "错误：load_yaml_config 需要提供配置文件路径" >&2
        return 1
    fi

    if [[ ! -f "${config_file}" ]]; then
        echo "错误：配置文件不存在: ${config_file}" >&2
        return 1
    fi

    local line
    local section=""
    local key=""
    local value=""

    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="${line%"${line##*[![:space:]]}"}"

        [[ -z "${line}" ]] && continue

        if [[ "${line}" =~ ^([A-Za-z0-9_]+):[[:space:]]*$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "${line}" =~ ^[[:space:]]{2}([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
                value="${BASH_REMATCH[1]}"
            elif [[ "${value}" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            if [[ -z "${section}" ]]; then
                echo "错误：配置项 ${key} 缺少所属 section: ${config_file}" >&2
                return 1
            fi

            printf -v "${section}_${key}" '%s' "${value}"
            export "${section}_${key}"
        fi
    done < "${config_file}"
}
