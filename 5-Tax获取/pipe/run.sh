#!/usr/bin/env bash
#*==========Accession ID获取Taxonomy信息脚本==========*

set -euo pipefail


BASE_DIR="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/5-Tax获取"

ACCESSION_FILE="/mnt/c/Users/Administrator/Desktop/conf/AccessionID.txt"
NAMES_DMP="${BASE_DIR}/download/names.dmp"
NODES_DMP="${BASE_DIR}/download/nodes.dmp"
OUT_DIR="/mnt/c/Users/Administrator/Desktop/output"
OUTPUT_FILE="${OUT_DIR}/Taxonomy_Results.csv"
BIOSAMPLE_OUTPUT="${OUT_DIR}/BioSample_Map.csv"
EMAIL="giantlinlinlin@gmail.com"
API_KEY="29b326d54e7a21fc6c8b9afe7d71f441d809"
DELAY="0.34"
DB_PRIORITY="nuccore assembly protein"

usage() {
  cat <<'EOF'
Usage: run.sh [options]
  --accession-file FILE   Accession列表文件（默认: conf/AccessionID.txt）
  --names-dmp FILE        names.dmp路径（默认: download/names.dmp）
  --nodes-dmp FILE        nodes.dmp路径（默认: download/nodes.dmp）
  --outdir DIR            输出目录（默认: results）
  --output FILE           分类结果文件（默认: results/Taxonomy_Results.csv）
  --biosample-output FILE BioSample映射结果文件（默认: results/BioSample_Map.csv）
  --email STR             提交给NCBI的email（可选）
  --api-key STR           NCBI API Key（可选）
  --delay FLOAT           请求间隔秒数（默认: 0.34）
  --db-priority LIST      E-utilities查询数据库优先级，空格分隔（默认: "nuccore assembly protein"）
  -h, --help              查看帮助
示例:
  ./run.sh --email you@example.com --api-key KEY123
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --accession-file) ACCESSION_FILE="$2"; shift 2;;
    --names-dmp) NAMES_DMP="$2"; shift 2;;
    --nodes-dmp) NODES_DMP="$2"; shift 2;;
    --outdir) OUT_DIR="$2"; shift 2;;
    --output) OUTPUT_FILE="$2"; shift 2;;
    --biosample-output) BIOSAMPLE_OUTPUT="$2"; shift 2;;
    --email) EMAIL="$2"; shift 2;;
    --api-key) API_KEY="$2"; shift 2;;
    --delay) DELAY="$2"; shift 2;;
    --db-priority)
      shift
      DB_PRIORITY=""
      while [[ $# -gt 0 && "$1" != --* ]]; do
        DB_PRIORITY+="${1} "
        shift
      done
      DB_PRIORITY="${DB_PRIORITY%" "}"
      continue
      ;;
    -h|--help) usage; exit 0;;
    *)
      echo "未知参数: $1" >&2
      usage
      exit 1
      ;;
  esac
done

mkdir -p "${OUT_DIR}"

EMAIL_ARG=()
[[ -n "${EMAIL}" ]] && EMAIL_ARG=(--email "${EMAIL}")

API_KEY_ARG=()
[[ -n "${API_KEY}" ]] && API_KEY_ARG=(--api-key "${API_KEY}")

DB_ARGS=()
read -r -a DB_ARRAY <<< "${DB_PRIORITY}"
if [[ ${#DB_ARRAY[@]} -gt 0 ]]; then
  DB_ARGS=(--db-priority "${DB_ARRAY[@]}")
fi

python3 "${BASE_DIR}/python/taxonomy_fetcher.py" \
  --accession-file "${ACCESSION_FILE}" \
  --names-dmp "${NAMES_DMP}" \
  --nodes-dmp "${NODES_DMP}" \
  --output "${OUTPUT_FILE}" \
  --delay "${DELAY}" \
  "${EMAIL_ARG[@]}" \
  "${API_KEY_ARG[@]}" \
  "${DB_ARGS[@]}"

# 生成BioSample映射两列CSV
python3 "${BASE_DIR}/python/biosample_mapper.py" \
  --accession-file "${ACCESSION_FILE}" \
  --output "${BIOSAMPLE_OUTPUT}" \
  --delay "${DELAY}" \
  "${EMAIL_ARG[@]}" \
  "${API_KEY_ARG[@]}"
