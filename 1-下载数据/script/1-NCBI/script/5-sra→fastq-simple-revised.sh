#!/bin/bash
# 合并版：固定路径 + 并行 fastq-dump
# - 并行核心逻辑来自 pfastq-dump (移除参数解析，写死配置)
# - 遍历固定 SRA_DIR 下的全部 .sra 文件
# - 输出到固定 FASTQ_DIR，自动创建，最后清理临时目录
# - 默认参数：--split-3 --gzip，线程数 16
# - 错误时不停止，继续处理剩余文件
# 如果你在 Conda 环境下安装了 SRA Toolkit，建议在外部先激活：conda activate SRA

############################################
# 1) 固定配置（按需改成你机器的绝对路径）
############################################
# SRA 根目录（包含 .sra 文件）
SRA_DIR="/data_raid/7_luolintao/1_Baoman/2-Sequence/FASTQ"
# FASTQ 输出目录（会自动创建）
FASTQ_DIR="${SRA_DIR}/FASTQ"
# 临时目录（用于分片写入与合并）
TMPDIR="${SRA_DIR}/tmp_pfd"
# 线程数（并行分块与并发 fastq-dump 子进程数）
NTHREADS=32
# fastq-dump 透传参数（固定写死）
OPTIONS="--split-3 --gzip"
# 是否走 STDOUT（固定为 false：落盘到 FASTQ_DIR）
STDOUT="false"

# 如需"硬路径"指定二进制，可在此写死；若已在 PATH 中则保持如下即可
SRA_STAT_BIN="sra-stat"
FASTQ_DUMP_BIN="fastq-dump"

# 版本号（仅用于日志）
VERSION="0.1.6-merged"

# 统计变量
TOTAL_FILES=0
SUCCESS_FILES=0
FAILED_FILES=0
declare -a FAILED_LIST=()

############################################
# 2) 工具函数
############################################
print_version(){
  echo "pfastq-dump version ${VERSION} using fastq-dump "$(${FASTQ_DUMP_BIN} --version 2>/dev/null | awk '$1 ~ /^fastq/ { print $3 }' || echo "unknown")
}

check_binary_location(){
  local cmd="${1}"
  local cmd_path
  cmd_path=$(which "${cmd}" 2>/dev/null || :)
  if [[ ! -e "${cmd_path}" ]]; then
    echo "ERROR: ${cmd} not found." >&2
    return 1
  else
    # 不同版本输出格式略有差异，这里做宽松处理
    echo "Using $(${cmd} --version 2>/dev/null | tr -d '\n' || echo "${cmd} at ${cmd_path}")" >&2
    return 0
  fi
}

# 统计 SRA 里 spot 数
calc_spot_count(){
  local sra="${1}"
  # sra-stat --meta --quick 输出中，第3段以 ':' 分隔的前部是 spot 数；逐行累计
  local txt
  txt=$(${SRA_STAT_BIN} --meta --quick "${sra}" 2>/dev/null) || {
    echo "ERROR: Failed to get spot count for ${sra}" >&2
    echo "0"
    return 1
  }
  local total=0
  for line in ${txt}; do
    local n
    n=$(echo "${line}" | cut -d '|' -f 3 | cut -d ':' -f 1 2>/dev/null || echo "0")
    if [[ "${n}" =~ ^[0-9]+$ ]]; then
      total=$(( total + n ))
    fi
  done
  echo ${total}
}

# 并行分块执行 fastq-dump，并合并分块产物
parallel_fastq_dump(){
  local sra="${1}"
  local count="${2}"

  local sraid
  sraid=$(basename "${sra}" | sed -e 's:.sra$::')
  local td="${TMPDIR}/pfd.tmp/${sraid}"

  # 创建临时目录，如果失败则返回错误
  if ! mkdir -p "${td}"; then
    echo "ERROR: Failed to create temp directory ${td}" >&2
    return 1
  fi

  # 保护：当 count < NTHREADS 时，避免除零并限制实际并发
  local threads=${NTHREADS}
  if [[ ${count} -lt ${threads} ]]; then
    threads=${count}
  fi
  if [[ ${threads} -lt 1 ]]; then
    threads=1
  fi

  local avg=$(( count / threads ))
  local remain=$(( count % threads ))
  if [[ ${avg} -lt 1 ]]; then
    avg=1
    threads=$(( (count + avg - 1) / avg ))  # ceiling
  fi

  local out=()
  local last=1

  # 计算每个线程的块范围
  for i in $(seq ${threads}); do
    local spots=$(( last + avg - 1 ))
    if [[ ${i} == ${threads} ]]; then
      local plus_remain=$(( spots + remain ))
      out+=("${last},${plus_remain}")
    else
      out+=("${last},${spots}")
    fi
    last=$(( last + avg ))
  done
  echo "[${sraid}] blocks: ${out[*]}" >&2

  # 并发执行 fastq-dump
  local pids=()
  for min_max in "${out[@]}"; do
    local min
    local max
    min=$(echo "${min_max}" | cut -d ',' -f 1)
    max=$(echo "${min_max}" | cut -d ',' -f 2)
    local idx=$(( (min - 1) / avg + 1 ))

    local d="${td}/${idx}"
    if ! mkdir -p "${d}"; then
      echo "ERROR: Failed to create directory ${d}" >&2
      continue
    fi

    # -N/-X 指定 spot 范围，输出到分片目录
    (${FASTQ_DUMP_BIN} -N "${min}" -X "${max}" -O "${d}" ${OPTIONS} "${sra}" 2>&1 || echo "ERROR in thread ${idx} for ${sraid}" >&2) &
    pids+=($!)
  done

  # 等待子进程并汇总状态
  local failure=0
  for pid in "${pids[@]}"; do
    if ! wait "${pid}"; then
      let "failure+=1"
    fi
  done

  # 合并分片
  if [[ "${failure}" != "0" ]]; then
    echo "ERROR: ${failure} thread(s) failed during decompressing for ${sraid}" >&2
    return 1
  else
    # 检查第1片是否存在
    if [[ ! -d "${td}/1" ]]; then
      echo "ERROR: No output found in first chunk for ${sraid}" >&2
      return 1
    fi

    # 用第 1 片的文件名清单作为合并目标列表
    local files=()
    mapfile -t files < <(ls -1 "${td}/1" 2>/dev/null || :)
    
    if [[ ${#files[@]} -eq 0 ]]; then
      echo "ERROR: No files found in first chunk for ${sraid}" >&2
      return 1
    fi

    # 准备输出（非 STDOUT 模式：先创建空文件）
    if [[ "${STDOUT}" != "true" ]]; then
      if ! mkdir -p "${FASTQ_DIR}"; then
        echo "ERROR: Failed to create FASTQ directory ${FASTQ_DIR}" >&2
        return 1
      fi
      for fo in "${files[@]}"; do
        : > "${FASTQ_DIR}/${fo}" || {
          echo "ERROR: Failed to create output file ${FASTQ_DIR}/${fo}" >&2
          return 1
        }
      done
    fi

    # 合并文件
    for min_max in "${out[@]}"; do
      local min
      min=$(echo "${min_max}" | cut -d ',' -f 1)
      local idx=$(( (min - 1) / avg + 1 ))
      for fo in "${files[@]}"; do
        if [[ -f "${td}/${idx}/${fo}" ]]; then
          if [[ "${STDOUT}" == "true" ]]; then
            cat "${td}/${idx}/${fo}" || echo "ERROR: Failed to cat ${td}/${idx}/${fo}" >&2
          else
            cat "${td}/${idx}/${fo}" >> "${FASTQ_DIR}/${fo}" || {
              echo "ERROR: Failed to append ${td}/${idx}/${fo} to ${FASTQ_DIR}/${fo}" >&2
              return 1
            }
          fi
        else
          echo "WARN: Missing file ${td}/${idx}/${fo}" >&2
        fi
      done
    done
  fi
  
  return 0
}

############################################
# 3) 主流程
############################################
print_version

# 检查必要工具，如果缺失则退出
if ! check_binary_location "${SRA_STAT_BIN}"; then
  echo "FATAL: Cannot proceed without ${SRA_STAT_BIN}" >&2
  exit 1
fi

if ! check_binary_location "${FASTQ_DUMP_BIN}"; then
  echo "FATAL: Cannot proceed without ${FASTQ_DUMP_BIN}" >&2
  exit 1
fi

echo "SRA_DIR : ${SRA_DIR}" >&2
echo "FASTQ_DIR: ${FASTQ_DIR}" >&2
echo "TMPDIR  : ${TMPDIR}" >&2
echo "THREADS : ${NTHREADS}" >&2
echo "OPTIONS : ${OPTIONS}" >&2

# 检查 SRA_DIR 是否存在
if [[ ! -d "${SRA_DIR}" ]]; then
  echo "FATAL: SRA_DIR ${SRA_DIR} does not exist" >&2
  exit 1
fi

# 创建必要目录
if ! mkdir -p "${FASTQ_DIR}"; then
  echo "FATAL: Failed to create FASTQ_DIR ${FASTQ_DIR}" >&2
  exit 1
fi

if ! mkdir -p "${TMPDIR}"; then
  echo "FATAL: Failed to create TMPDIR ${TMPDIR}" >&2
  exit 1
fi

# 构建清单（固定为 SRA_DIR 下所有 .sra）
SRA_LIST_FILE="${SRA_DIR}/sra_files.txt"
find "${SRA_DIR}" -type f -name "*.sra" | sort > "${SRA_LIST_FILE}" 2>/dev/null || {
  echo "ERROR: Failed to find .sra files in ${SRA_DIR}" >&2
  exit 1
}

# 检查是否有文件要处理
if [[ ! -s "${SRA_LIST_FILE}" ]]; then
  echo "WARN: No .sra files found in ${SRA_DIR}" >&2
  exit 0
fi

TOTAL_FILES=$(wc -l < "${SRA_LIST_FILE}")
echo "Found ${TOTAL_FILES} .sra files to process" >&2

# 逐个处理
while IFS= read -r srafile || [[ -n "$srafile" ]]; do
  # 跳过空行
  [[ -z "$srafile" ]] && continue
  
  echo "[START] ${srafile}" >&2
  
  # 检查文件是否存在
  if [[ ! -f "${srafile}" ]]; then
    echo "[ERROR] File not found: ${srafile}" >&2
    FAILED_FILES=$((FAILED_FILES + 1))
    FAILED_LIST+=("${srafile} (file not found)")
    continue
  fi
  
  # 获取 spot count，失败时跳过
  spot_count=$(calc_spot_count "${srafile}")
  if [[ $? -ne 0 ]] || [[ -z "${spot_count}" ]] || [[ "${spot_count}" -le 0 ]]; then
    echo "[ERROR] ${srafile} failed to get spot count or spot_count<=0 (${spot_count})" >&2
    FAILED_FILES=$((FAILED_FILES + 1))
    FAILED_LIST+=("${srafile} (spot count error: ${spot_count})")
    continue
  fi

  echo "[INFO ] ${srafile} spots=${spot_count}" >&2

  # 执行并行处理，失败时记录但不退出
  if parallel_fastq_dump "${srafile}" "${spot_count}"; then
    echo "[DONE ] ${srafile}" >&2
    SUCCESS_FILES=$((SUCCESS_FILES + 1))
  else
    echo "[ERROR] ${srafile} processing failed" >&2
    FAILED_FILES=$((FAILED_FILES + 1))
    FAILED_LIST+=("${srafile} (processing failed)")
  fi
  
  # 清理该文件的临时目录（即使失败也清理，避免磁盘空间问题）
  sraid=$(basename "${srafile}" | sed -e 's:.sra$::')
  rm -rf "${TMPDIR}/pfd.tmp/${sraid}" 2>/dev/null || :
  
done < "${SRA_LIST_FILE}"

# 清理临时目录
rm -rf "${TMPDIR}/pfd.tmp" 2>/dev/null || :

# 打印统计结果
echo "============================================" >&2
echo "Processing Summary:" >&2
echo "Total files: ${TOTAL_FILES}" >&2
echo "Successful: ${SUCCESS_FILES}" >&2
echo "Failed: ${FAILED_FILES}" >&2
echo "============================================" >&2

if [[ ${FAILED_FILES} -gt 0 ]]; then
  echo "Failed files:" >&2
  for failed_item in "${FAILED_LIST[@]}"; do
    echo "  - ${failed_item}" >&2
  done
  echo "============================================" >&2
fi

if [[ ${SUCCESS_FILES} -gt 0 ]]; then
  echo "[成功转换 ${SUCCESS_FILES}/${TOTAL_FILES} 个 SRA 文件为 FASTQ 并保存到：${FASTQ_DIR}]"
else
  echo "[警告：没有文件成功转换]" >&2
fi

# 根据成功情况设置退出码（但不影响脚本继续运行到此处）
if [[ ${SUCCESS_FILES} -eq 0 ]] && [[ ${TOTAL_FILES} -gt 0 ]]; then
  exit 1  # 所有文件都失败
elif [[ ${FAILED_FILES} -gt 0 ]]; then
  exit 2  # 部分文件失败
else
  exit 0  # 全部成功
fi

