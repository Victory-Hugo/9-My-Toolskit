


unset http_proxy
unset https_proxy

ascli \
  -Pera server download \
  --log-level=info \
  vol1/fastq/SRR916/002/SRR9169172/SRR9169172.fastq.gz \
  --to-folder=/mnt/c/Users/Administrator/Desktop/

ascli -Pera server download \
  --log-level=info \
  --sources=@lines:@file:/mnt/c/Users/Administrator/Desktop/download.txt \
  --to-folder=/mnt/c/Users/Administrator/Desktop/
