#!/usr/bin/env bash

set -euo pipefail

PIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${PIPE_DIR}/.." && pwd)"
DEFAULT_CONFIG_FILE="${PROJECT_DIR}/conf/1-组装数据下载.yaml"
CONFIG_LOADER="${PROJECT_DIR}/script/load_config.sh"

usage() {
    cat <<EOF
用法：
  bash pipe/1-组装数据下载.sh [--config conf/1-组装数据下载.yaml]

说明：
  由 YAML 配置驱动以下步骤：
  1. 下载 Assembly 数据包
  2. 下载 BioSample XML 与映射表
  3. 解压并整理下载结果
EOF
}

if [[ ! -f "${CONFIG_LOADER}" ]]; then
    echo "错误：配置加载脚本不存在: ${CONFIG_LOADER}" >&2
    exit 1
fi

CONFIG_FILE="${DEFAULT_CONFIG_FILE}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config|-c)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "错误：未知参数: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# shellcheck source=/dev/null
source "${CONFIG_LOADER}"
load_yaml_config "${CONFIG_FILE}"

resolve_path() {
    local raw_path="$1"
    local base_dir="$2"

    if [[ -z "${raw_path}" ]]; then
        printf '%s\n' ""
    elif [[ "${raw_path}" = /* ]]; then
        printf '%s\n' "${raw_path}"
    else
        printf '%s\n' "${base_dir}/${raw_path}"
    fi
}

require_file() {
    local path="$1"
    local label="$2"
    if [[ ! -f "${path}" ]]; then
        echo "错误：${label}不存在: ${path}" >&2
        exit 1
    fi
}

require_dir() {
    local path="$1"
    local label="$2"
    if [[ ! -d "${path}" ]]; then
        echo "错误：${label}不存在: ${path}" >&2
        exit 1
    fi
}

require_command_or_file() {
    local value="$1"
    local label="$2"

    if [[ -z "${value}" ]]; then
        echo "错误：${label}未配置" >&2
        exit 1
    fi

    if [[ "${value}" = */* ]]; then
        require_file "${value}" "${label}"
    elif ! command -v "${value}" >/dev/null 2>&1; then
        echo "错误：找不到${label}: ${value}" >&2
        exit 1
    fi
}

run_cmd() {
    local -a cmd=("$@")
    printf '命令:'
    printf ' %q' "${cmd[@]}"
    printf '\n'
    if [[ "${DRY_RUN}" = "true" ]]; then
        return 0
    fi
    "${cmd[@]}"
}

BASE_DIR="$(resolve_path "${project_base_dir:-.}" "${PROJECT_DIR}")"
ASSEMBLY_ID_FILE="$(resolve_path "${project_assembly_id_file:-}" "${BASE_DIR}")"
DOWNLOAD_DIR="$(resolve_path "${paths_download_dir:-}" "${BASE_DIR}")"
META_DIR="$(resolve_path "${paths_meta_dir:-}" "${BASE_DIR}")"
LOG_DIR="$(resolve_path "${paths_log_dir:-log}" "${BASE_DIR}")"
PYTHON_BIN="${tools_python_bin:-python3}"
DOWNLOAD_SCRIPT="$(resolve_path "${paths_download_script:-python/7-下载NCBI的Assembly.py}" "${BASE_DIR}")"
BIOSAMPLE_SCRIPT="$(resolve_path "${paths_biosample_script:-script/7-2-GCA_GCF→SAMN+xml.sh}" "${BASE_DIR}")"
EXTRACT_SCRIPT="$(resolve_path "${paths_extract_script:-python/extract_and_organize.py}" "${BASE_DIR}")"
ESEARCH_BIN="${tools_esearch_bin:-esearch}"
EFETCH_BIN="${tools_efetch_bin:-efetch}"
XTRACT_BIN="${tools_xtract_bin:-xtract}"
NCBI_EMAIL="${tools_ncbi_email:-}"
NCBI_API_KEY="${tools_ncbi_api_key:-}"

RUN_DOWNLOAD="${runtime_run_download:-true}"
RUN_BIOSAMPLE="${runtime_run_biosample:-true}"
RUN_EXTRACT="${runtime_run_extract:-true}"
UNSET_PROXY="${runtime_unset_proxy:-true}"
DOWNLOAD_WORKERS="${runtime_download_workers:-10}"
DOWNLOAD_RESUME="${runtime_download_resume:-true}"
FORCE_REDOWNLOAD="${runtime_force_redownload:-false}"
BIOSAMPLE_PARALLEL="${runtime_biosample_parallel:-5}"
EXTRACT_WORKERS="${runtime_extract_workers:-8}"
EXTRACT_OVERWRITE="${runtime_extract_overwrite:-false}"
EXTRACT_BACKUP="${runtime_extract_backup:-false}"
EXTRACT_VERBOSE="${runtime_extract_verbose:-false}"
DRY_RUN="${runtime_dry_run:-false}"

if [[ "${UNSET_PROXY}" = "true" ]]; then
    unset http_proxy || true
    unset https_proxy || true
fi

require_dir "${BASE_DIR}" "项目根目录"
require_file "${ASSEMBLY_ID_FILE}" "Assembly 编号文件"
require_file "${DOWNLOAD_SCRIPT}" "Assembly 下载模块"
require_file "${BIOSAMPLE_SCRIPT}" "BioSample 下载模块"
require_file "${EXTRACT_SCRIPT}" "解压整理模块"
require_command_or_file "${PYTHON_BIN}" "Python 解释器"
require_command_or_file "${ESEARCH_BIN}" "esearch"
require_command_or_file "${EFETCH_BIN}" "efetch"
require_command_or_file "${XTRACT_BIN}" "xtract"

mkdir -p "${DOWNLOAD_DIR}" "${META_DIR}" "${LOG_DIR}"

echo "======================================"
echo "组装数据下载管道启动"
echo "======================================"
echo "配置文件:       ${CONFIG_FILE}"
echo "项目根目录:     ${BASE_DIR}"
echo "Assembly 列表:  ${ASSEMBLY_ID_FILE}"
echo "下载目录:       ${DOWNLOAD_DIR}"
echo "Meta 目录:      ${META_DIR}"
echo "日志目录:       ${LOG_DIR}"
echo "Dry run:        ${DRY_RUN}"
echo ""

if [[ "${RUN_DOWNLOAD}" = "true" ]]; then
    echo "[1/3] 下载 Assembly 数据"
    DOWNLOAD_CMD=(
        "${PYTHON_BIN}" "${DOWNLOAD_SCRIPT}"
        --base-path "${DOWNLOAD_DIR}"
        --file-path "${ASSEMBLY_ID_FILE}"
        --workers "${DOWNLOAD_WORKERS}"
    )
    if [[ -n "${NCBI_EMAIL}" ]]; then
        DOWNLOAD_CMD+=(--email "${NCBI_EMAIL}")
    fi
    if [[ -n "${NCBI_API_KEY}" ]]; then
        DOWNLOAD_CMD+=(--api-key "${NCBI_API_KEY}")
    fi
    if [[ "${DOWNLOAD_RESUME}" = "true" ]]; then
        DOWNLOAD_CMD+=(--resume)
    fi
    if [[ "${FORCE_REDOWNLOAD}" = "true" ]]; then
        DOWNLOAD_CMD+=(--force-redownload)
    fi
    run_cmd "${DOWNLOAD_CMD[@]}"
    echo ""
fi

if [[ "${RUN_BIOSAMPLE}" = "true" ]]; then
    echo "[2/3] 下载 BioSample XML 与映射信息"
    BIOSAMPLE_CMD=(
        bash "${BIOSAMPLE_SCRIPT}"
        --input-file "${ASSEMBLY_ID_FILE}"
        --output-dir "${META_DIR}"
        --parallel "${BIOSAMPLE_PARALLEL}"
        --esearch-bin "${ESEARCH_BIN}"
        --efetch-bin "${EFETCH_BIN}"
        --xtract-bin "${XTRACT_BIN}"
    )
    if [[ -n "${NCBI_API_KEY}" ]]; then
        BIOSAMPLE_CMD+=(--api-key "${NCBI_API_KEY}")
    fi
    run_cmd "${BIOSAMPLE_CMD[@]}"
    echo ""
fi

if [[ "${RUN_EXTRACT}" = "true" ]]; then
    echo "[3/3] 解压并整理下载结果"
    EXTRACT_CMD=(
        "${PYTHON_BIN}" "${EXTRACT_SCRIPT}"
        "${DOWNLOAD_DIR}"
        --max-workers "${EXTRACT_WORKERS}"
    )
    if [[ "${EXTRACT_OVERWRITE}" = "true" ]]; then
        EXTRACT_CMD+=(--overwrite)
    fi
    if [[ "${EXTRACT_BACKUP}" = "true" ]]; then
        EXTRACT_CMD+=(--backup)
    fi
    if [[ "${EXTRACT_VERBOSE}" = "true" ]]; then
        EXTRACT_CMD+=(--verbose)
    fi
    run_cmd "${EXTRACT_CMD[@]}"
    echo ""
fi

echo "完成。"
echo "下载目录: ${DOWNLOAD_DIR}"
echo "Meta 目录: ${META_DIR}"
