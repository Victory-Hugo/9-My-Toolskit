#!/usr/bin/env bash

# =============================================================
# 脚本功能：将目录下所有 XML 文件批量提取为单一 TSV 文件
# 用法：
#   bash pipe/4-xml→tsv.sh
#   bash pipe/4-xml→tsv.sh <xml_dir> <output_tsv>
# =============================================================

set -euo pipefail

PIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${PIPE_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_DIR}/conf/4-xml→tsv.yaml"
CONFIG_LOADER="${PROJECT_DIR}/script/load_config.sh"

if [ ! -f "${CONFIG_LOADER}" ]; then
    echo "错误：配置加载脚本不存在: ${CONFIG_LOADER}"
    exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_LOADER}"
load_yaml_config "${CONFIG_FILE}"

resolve_path() {
    local raw_path="$1"
    local base_dir="$2"

    if [ -z "${raw_path}" ]; then
        printf '%s\n' ""
    elif [[ "${raw_path}" = /* ]]; then
        printf '%s\n' "${raw_path}"
    else
        printf '%s\n' "${base_dir}/${raw_path}"
    fi
}

BASE_DIR="${project_base_dir:-${PROJECT_DIR}}"
PYTHON3="${tools_python_bin:-python3}"
PY_SCRIPT="$(resolve_path "${paths_python_dir:-python}" "${BASE_DIR}")/xml_to_tsv.py"
DEFAULT_XML_DIR="$(resolve_path "${paths_xml_dir:-}" "${BASE_DIR}")"
DEFAULT_OUTPUT_TSV="$(resolve_path "${paths_output_tsv:-}" "${BASE_DIR}")"
JOBS="${runtime_jobs:-8}"
VERBOSE="${runtime_verbose:-false}"

# =============================================================
# 参数解析：支持位置参数覆盖默认配置
#   $1 = XML 文件目录
#   $2 = 输出 TSV 路径
# =============================================================
XML_DIR="${1:-${DEFAULT_XML_DIR}}"
OUTPUT_TSV="${2:-${DEFAULT_OUTPUT_TSV}}"

# =============================================================
# 参数验证
# =============================================================
echo "======================================"
echo "XML → TSV 提取管道启动"
echo "======================================"
echo "配置文件:   ${CONFIG_FILE}"

if [ -z "${XML_DIR}" ]; then
    echo "错误：未指定 XML 输入目录"
    echo "用法: bash pipe/4-xml→tsv.sh <xml_dir> <output_tsv>"
    exit 1
fi

if [ -z "${OUTPUT_TSV}" ]; then
    echo "错误：未指定输出 TSV 路径"
    echo "用法: bash pipe/4-xml→tsv.sh <xml_dir> <output_tsv>"
    exit 1
fi

if [ ! -d "${XML_DIR}" ]; then
    echo "错误：输入目录不存在: ${XML_DIR}"
    exit 1
fi

if [ ! -f "${PY_SCRIPT}" ]; then
    echo "错误：Python 模块不存在: ${PY_SCRIPT}"
    exit 1
fi

XML_COUNT=$(find "${XML_DIR}" -name "*.xml" | wc -l)
if [ "${XML_COUNT}" -eq 0 ]; then
    echo "错误：输入目录中未找到任何 .xml 文件: ${XML_DIR}"
    exit 1
fi

echo "输入目录:   ${XML_DIR}"
echo "XML 文件数: ${XML_COUNT}"
echo "输出文件:   ${OUTPUT_TSV}"
echo "并行进程数: ${JOBS}"
echo ""

mkdir -p "$(dirname "${OUTPUT_TSV}")"

# =============================================================
# 执行 XML → TSV 提取
# =============================================================
CMD=(
    "${PYTHON3}" "${PY_SCRIPT}"
    --input-dir "${XML_DIR}"
    --output-tsv "${OUTPUT_TSV}"
    --jobs "${JOBS}"
)

if [ "${VERBOSE}" = "true" ]; then
    CMD+=(--verbose)
fi

"${CMD[@]}"

EXIT_CODE=$?

echo ""
if [ "${EXIT_CODE}" -eq 0 ]; then
    echo "完成！输出文件: ${OUTPUT_TSV}"
else
    echo "错误：XML 转 TSV 失败（退出码: ${EXIT_CODE}）"
    exit "${EXIT_CODE}"
fi
