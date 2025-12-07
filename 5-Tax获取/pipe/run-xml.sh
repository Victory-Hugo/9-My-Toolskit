#!/usr/bin/env bash
#*==========基于本地BioSample XML文件获取完整Meta信息脚本==========*

set -euo pipefail

BASE_DIR="/mnt/f/OneDrive/文档（科研）/脚本/Download/9-My-Toolskit/5-Tax获取"
META_DIR="/mnt/d/5-NCBI-Reference/2-Arc/meta"
MAP_CSV="${META_DIR}/assembly_biosample_map.csv"
NAMES_DMP="${BASE_DIR}/download/names.dmp"
NODES_DMP="${BASE_DIR}/download/nodes.dmp"
OUTPUT_FILE="${META_DIR}/final_meta.csv"
LOG_LEVEL="INFO"

usage() {
  cat <<'EOF'
Usage: run-xml.sh [options]
  --meta-dir DIR    BioSample XML所在目录 (默认: /mnt/d/5-NCBI-Reference/1-Bac/meta)
  --map-csv FILE    assembly_biosample_map.csv路径 (默认: META_DIR/assembly_biosample_map.csv)
  --names-dmp FILE  names.dmp路径 (默认: BASE_DIR/download/names.dmp)
  --nodes-dmp FILE  nodes.dmp路径 (默认: BASE_DIR/download/nodes.dmp)
  --output FILE     输出final_meta.csv路径 (默认: META_DIR/final_meta.csv)
  --log-level LVL   日志等级: DEBUG|INFO|WARNING|ERROR|CRITICAL (默认: INFO)
  -h, --help        查看帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --meta-dir) META_DIR="$2"; shift 2;;
    --map-csv) MAP_CSV="$2"; shift 2;;
    --names-dmp) NAMES_DMP="$2"; shift 2;;
    --nodes-dmp) NODES_DMP="$2"; shift 2;;
    --output) OUTPUT_FILE="$2"; shift 2;;
    --log-level) LOG_LEVEL="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *)
      echo "未知参数: $1" >&2
      usage
      exit 1
      ;;
  esac
done

python3 "${BASE_DIR}/python/xml_meta_builder.py" \
  --meta-dir "${META_DIR}" \
  --map-csv "${MAP_CSV}" \
  --names-dmp "${NAMES_DMP}" \
  --nodes-dmp "${NODES_DMP}" \
  --output "${OUTPUT_FILE}" \
  --log-level "${LOG_LEVEL}"
