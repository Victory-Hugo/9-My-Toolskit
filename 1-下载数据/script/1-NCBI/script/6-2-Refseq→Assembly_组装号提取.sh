#!/bin/bash
set -u

INPUT="/mnt/d/迅雷下载/鲍曼组装/ncbi_refseq_assembly_mapping_gnu_parallel.csv"
OUT_ASSEMBLY="/mnt/d/迅雷下载/鲍曼组装/conf/AB_Assembly.txt"
OUT_BIOSAMPLE="/mnt/d/迅雷下载/鲍曼组装/conf/AB_Biosample.txt"

# 临时文件
tmp_header=$(mktemp)
tmp_out1=$(mktemp)
tmp_out2=$(mktemp)

cleanup() {
  rm -f "$tmp_header" "$tmp_out1" "$tmp_out2"
}
trap cleanup EXIT

# 读取 header 并去 BOM、CRLF
head -n1 "$INPUT" | sed $'s/\xEF\xBB\xBF//' | sed 's/\r$//' > "$tmp_header"
header=$(cat "$tmp_header")

# 判定分隔符（优先逗号）
if printf '%s' "$header" | grep -q ','; then
  # 逗号分隔，优先使用 gawk（FPAT 更稳健）
  if command -v gawk >/dev/null 2>&1; then
    gawk -v FPAT='("([^"]|"")*"|[^,]*)' -v OUT1="$tmp_out1" -v OUT2="$tmp_out2" '
      NR==1{
        for(i=1;i<=NF;i++){
          f=$i
          # 清理 field 两端引号与双引号转义
          gsub(/^"/,"",f); gsub(/"$/,"",f); gsub(/""/,"\"",f)
          if(f=="Assembly_Accession") colA=i
          if(f=="BioSample") colB=i
        }
        if(!(colA && colB)){
          print "ERROR: 未找到 Assembly_Accession 或 BioSample 列" > "/dev/stderr"
          exit 2
        }
        next
      }
      {
        a=$colA; b=$colB
        gsub(/^"/,"",a); gsub(/"$/,"",a); gsub(/""/,"\"",a)
        gsub(/^"/,"",b); gsub(/"$/,"",b); gsub(/""/,"\"",b)
        print a >> OUT1
        print b >> OUT2
      }
    ' "$INPUT"
  else
    # 没有 gawk 的 fallback（对常见 CSV 可用）
    awk -F, -v OUT1="$tmp_out1" -v OUT2="$tmp_out2" 'BEGIN{OFS=FS}
      NR==1{
        for(i=1;i<=NF;i++){
          g=$i; sub(/^"/,"",g); sub(/"$/,"",g); gsub(/""/,"\"",g)
          if(g=="Assembly_Accession") colA=i
          if(g=="BioSample") colB=i
        }
        if(!(colA && colB)){ print "ERROR: 未找到 Assembly_Accession 或 BioSample 列" > "/dev/stderr"; exit 2 }
        next
      }
      {
        a=$colA; b=$colB
        sub(/^"/,"",a); sub(/"$/,"",a); gsub(/""/,"\"",a)
        sub(/^"/,"",b); sub(/"$/,"",b); gsub(/""/,"\"",b)
        print a >> OUT1
        print b >> OUT2
      }
    ' "$INPUT"
  fi

else
  # Tab 分隔情况
  awk -F'\t' -v OUT1="$tmp_out1" -v OUT2="$tmp_out2" '
    NR==1{
      for(i=1;i<=NF;i++){
        g=$i; sub(/\r$/,"",g)
        if(g=="Assembly_Accession") colA=i
        if(g=="BioSample") colB=i
      }
      if(!(colA && colB)){ print "ERROR: 未找到 Assembly_Accession 或 BioSample 列" > "/dev/stderr"; exit 2 }
      next
    }
    { print $colA >> OUT1; print $colB >> OUT2 }
  ' "$INPUT"
fi

# 将临时输出移动到目标路径（原子替换）
mv "$tmp_out1" "$OUT_ASSEMBLY"
mv "$tmp_out2" "$OUT_BIOSAMPLE"

echo "已生成:"
echo "  Assembly 列 -> $OUT_ASSEMBLY"
echo "  BioSample 列 -> $OUT_BIOSAMPLE"
