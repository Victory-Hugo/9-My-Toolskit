#######指定人群分析步骤
#将mtDNA（第26条染色体）提取至单独的文件
plink --bfile Guangxi_sixpops --chr 26 --make-bed --out Affy_mtDNA
#过滤掉低质量SNP
plink --bfile Affy_mtDNA --geno 0.1 --mind 0.1 --make-bed --out llumina_mtDNA_Filter

#######convert bed bim fam fiels into vcf files
#将bed bim fam文件转化成VCF文件
plink --bfile llumina_mtDNA_Filter --recode vcf-iid --out llumina_mtDNA_Filter 

#该shellscript函数的主要目的是从Guangxi_sixpops.vcf文件中过滤掉含有特定字符“X”的第五列（allele信息）的行，并将处理后的结果保存到新的文件llumina_mtDNA_Filtercopy.vcf中。
cat Affy_mtDNA.vcf |perl -F'\t' -alne 'if($_=~/^#/){print "$_";} elsif($F[4]=~/X/){ } else{print $_;}' > llumina_mtDNA_Filtercopy.vcf

#将文件复制一份并把第五列的X替换为.，便于后续分析
# cp llumina_mtDNA_Filter.vcf llumina_mtDNA_Filtercopy.vcf
awk -F '\t' '/^#/ {print;next;} {OFS="\t";if($5=="X") $5="."; print;}' < llumina_mtDNA_Filtercopy.vcf >llumina_mtDNA_Filter.vcf


##运行haploGrouper并用haploGrouper标签标记ID和线粒体单倍群准备Beast和popArt文件
#把VCF文件转换成compound-genotypes格式，这种格式可以更好地保留和表达复合等位基因信息，尤其是在处理线粒体DNA（mtDNA）或单体型数据时更为重要。
plink --vcf  llumina_mtDNA_Filter.vcf --recode compound-genotypes --double-id  --out  llumina_mtDNA_Filter_recode

#generate the -i individual files该脚本的主要目的是从VCF文件中提取样本ID列表，并将这些ID转换成每行一个ID的形式保存到新文件中。
bcftools view -h   llumina_mtDNA_Filter.vcf |tail -n 1 |cut -f10-|perl -npe "s/\t/\n/g" >   llumina_mtDNA_Filter.id_hGrpr2

#利用python3 运行hGrpr2.py，注意参数的输入顺序，参数与参数之间之间用空格隔开，不分段。
python3 /home/biosoftware/haploGrouper/hGrpr2.py \
                 -v  llumina_mtDNA_Filter.vcf \
                 -t /home/biosoftware/haploGrouper/data/mt_phyloTree_b17_Tree2.txt \
                 -l /home/biosoftware/haploGrouper/data/mt_phyloTree_b17_Mutation.txt \
                 -f /home/biosoftware/haploGrouper/data/rCRS.fasta \
                 -i  llumina_mtDNA_Filter.id_hGrpr2 \
                 -o  llumina_mtDNA_Filter_mt_hg_hGrpr2.txt \
                 -x  llumina_mtDNA_Filter_mt_allScores_hGrpr2.txt  

#生成hGrpr2标记的ID文件。单倍群分型结果文件产生。
cat  llumina_mtDNA_Filter_mt_hg_hGrpr2.txt | awk 'BEGIN{FS=" ";OFS="\t";}{print $1, $2;}' >  llumina_mtDNA_Filter_mt_hg_hGrpr2top2old

cat llumina_mtDNA_Filter_mt_hg_hGrpr2top2old |sed 's/\"//g' > llumina_mtDNA_Filter_mt_hg_hGrpr2top2

rm llumina_mtDNA_Filter_mt_hg_hGrpr2top2old


#——————————————————————————————分割线——————————————————————————————————————————————————————————————————————————————————————————————————————
#——————————————————————————————下面将进行Beast和popArt文件的制作————————————————————————————————————————————————————————————————————————————

#generate the beast files 注意ID值的排序问题 haploGrouper顺序不改变

paste -d' '  <(tail --lines=+2   llumina_mtDNA_Filter_mt_hg_hGrpr2top2) <(cat  llumina_mtDNA_Filter_recode.ped |cut -d' ' -f3-) |perl -npe "s/\t/_/"|cut -d' ' -f1,6-|perl -npe "s/^/>/;s/ ([ATCG]){2}/ \1/g;s/ 00/ N/g"|perl -npe  "s/ /\t/;s/ //g;"|perl -npe "s/.*\t\?+$//"|grep -v "^$"|perl -npe "s/\t/\n/"> llumina_mtDNA_Filter_Beast_haploGrouper_Label.fasta 

##Convert_fasta version NEXUS
#Convert fasta files to NEXUS files in the popART anlysis for Network relationship reconstruction
#Genarate fasta files for phylo
cat llumina_mtDNA_Filter_recode.ped|cut -d' ' -f1,7-|perl -npe "s/^/>/;s/ ([ATCG]){2}/ \1/g;s/ 00/ N/g"|perl -npe "s/ /\t/;s/ //g"|perl -npe "s/\t/\n/" > llumina_mtDNA_Filter_recode.fasta
python /home/biosoftware/vcf2phylip/fasta_nexus_converter/fasta_to_nexus/Main.py  llumina_mtDNA_Filter_Beast_haploGrouper_Label.fasta 
mv example.nex  llumina_mtDNA_Filter_Beast_haploGrouper_Label.nexus


#Generate ind_haplogroup population file, #注意空格非Tab分割
cat llumina_mtDNA_Filter.fam | awk 'BEGIN{FS=" ";OFS="\t";}{print $2,$1;}' > indpopnew
paste -d' '  <(tail --lines=+2  llumina_mtDNA_Filter_mt_hg_hGrpr2top2) <(cat indpopnew |cut -d' ' -f1-) >llumina_mtDNA_Filter_Beast_haploGrouper.Traits
cat  llumina_mtDNA_Filter_Beast_haploGrouper.Traits | awk 'BEGIN{FS=" ";OFS="\t";}{print $1"_"$2, $4;}' >  llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_popOld
sed 's/[\t ]\+/ /g' llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_popOld >  llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop
rm llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_popOld

#Generated ind pop in different level
#cat llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop |perl -npe "s/^(.*? .*?_.*?)_.*/\1/" > llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level2
cat llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop |perl -npe "s/^(.*? .*?)_.*/\1/" > llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level1

#Generate traits ind_Trats matrix
cat llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level1|perl -npe "s/ +/\t/g;"|cut -f2|sort |uniq|perl -npe "s/\n/,/"|perl -npe "s/$/\n/;s/^/,/" >tmp_pop.txt; cat <(cat tmp_pop.txt |perl -npe "s/^,//;s/,$//") <(cat llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level1|perl -npe "s/ +/\t/g"|cut -f1,2|while read sample pop;do cat tmp_pop.txt|perl -npe "s/,$pop,/,#,/"|perl -npe "s/[^#,\n]+/0/g;s/#/1/;s/^,/$sample\t/;s/,$//" ;done) > llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level1.Traits

#generated the Traits template
trait_num=`head -n 1 llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level1.Traits|perl -npe "s/,/\n/g"|wc -l `;trait_label=`head -n 1 llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level1.Traits|perl -npe "s/,/, /g"`;matrix_value=`cat llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level1.Traits|tail --lines=+2`;cat /home/biosoftware/ppgv1/popart/pop_Trait_template |perl -npe "s/trait_label/$trait_label/;s/matrix_value/$matrix_value/;s/trait_num/$trait_num/"  > llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level1.Traits.Matrix

#Generated the final version for popArt analysis
cat llumina_mtDNA_Filter_Beast_haploGrouper_Label.nexus llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level1.Traits.Matrix > llumina_mtDNA_Filter_Beast_haploGrouper_ind_Haplo_pop_Level1.Traits.Matrix.nexus










运行haplogrep并用haplogrep标签标记ID和线粒体单倍群准备Beast和popArt文件
第二步骤haplogrep全单倍群分型标记
利用ID和全单倍群标记新的ID
for x in {17..17}; do
/home/biosoftware/haplogrep-cmd/install/haplogrep classify --in llumina_mtDNA_Filter.vcf --format vcf --phylotree $x  --chip --extend-report --lineage 2 --out llumina_mtDNA_Filterlineage2_phylotree$x 
dot llumina_mtDNA_Filterlineage2_phylotree$x.dot -Tpdf > llumina_mtDNA_Filterlineage2_phylotree$x.pdf 
 /home/biosoftware/haplogrep-cmd/install/haplogrep classify --in llumina_mtDNA_Filter.vcf --format vcf --phylotree $x --chip --extend-report --lineage 1 --out llumina_mtDNA_Filterlineage1_phylotree$x 
 dot llumina_mtDNA_Filterlineage1_phylotree$x.dot -Tpdf > llumina_mtDNA_Filterlineage1_phylotree$x.pdf
done

###run Beast anlysis using the haplogrep label
cat llumina_mtDNA_Filterlineage2_phylotree17 | awk 'BEGIN{FS=" ";OFS="\t";}{print $1, $2;}' >  llumina_mtDNA_Filterlineage2_phylotree17First2
cat llumina_mtDNA_Filterlineage2_phylotree17First2 |sed 's/\"//g' > llumina_mtDNA_Filterlineage2_phylotree17First2new
rm llumina_mtDNA_Filterlineage2_phylotree17First2
###run with out sort inds
paste -d' '  <(tail --lines=+2  _llumina_mtDNA_Filterlineage2_phylotree17First2new) <(cat llumina_mtDNA_Filter_recode.ped |cut -d' ' -f3-) |perl -npe "s/\t/_/"|cut -d' ' -f1,6-|perl -npe "s/^/>/;s/ ([ATCG]){2}/ \1/g;s/ 00/ \?/g"|perl -npe  "s/ /\t/;s/ //g;"|perl -npe "s/.*\t\?+$//"|grep -v "^$"|perl -npe "s/\t/\n/">llumina_mtDNA_Filter_Beast_haplogrep_Label.fasta ;done

#Run Beast with two files allingment
paste -d' '  <(cat llumina_mtDNA_Filter_recode.ped|cut -d' ' -f1-2|while read pop sample;do grep "^$pop"$'\t' llumina_mtDNA_Filterlineage2_phylotree17First2new;done ) <(cat llumina_mtDNA_Filter_recode.ped |cut -d' ' -f3-) |perl -npe "s/\t/_/"|cut -d' ' -f1,6-|perl -npe "s/^/>/;s/ ([ATCG]){2}/ \1/g;s/ 00/ N/g"|perl -npe  "s/ /\t/;s/ //g;"|perl -npe "s/.*\t\?+$//"|grep -v "^$"|perl -npe "s/\t/\n/" > llumina_mtDNA_Filter_Beast_haplogrep_Label.fasta 

##Convert_fasta version NEXUS
#Convert fasta files to NEXUS files in the popART anlysis for Network relationship reconstruction
#Genarate fasta files for phylo
#cat llumina_mtDNA_Filter_recode.ped|cut -d' ' -f1,7-|perl -npe "s/^/>/;s/ ([ATCG]){2}/ \1/g;s/ 00/ N/g"|perl -npe "s/ /\t/;s/ //g"|perl -npe "s/\t/\n/" > llumina_mtDNA_Filter_recode.fasta
python /home/biosoftware/vcf2phylip/fasta_nexus_converter/fasta_to_nexus/Main.py  llumina_mtDNA_Filter_Beast_haplogrep_Label.fasta 
mv example.nex  llumina_mtDNA_Filter_Beast_haplogrep_Label.nexus

cat llumina_mtDNA_Filterlineage2_phylotree17 |perl -npe "s/\"//g;s/ +/\t/g"|tail --lines=+2 >tmp.txt;cat llumina_mtDNA_Filter.fam|while read pop sample info; do new_name=`grep "^$sample"$'\t' tmp.txt |cut -f2`;echo  $sample$'\t'$new_name;done > llumina_mtDNA_Filter_Beast_haplogrep_All_ind_haplo

cp llumina_mtDNA_Filter_Beast_haplogrep_All_ind_haplo llumina_mtDNA_Filter_Beast_haplogrep_All_ind_haplonew
sed -i "1iSampleID\tHaplogroup" llumina_mtDNA_Filter_Beast_haplogrep_All_ind_haplonew

#Generate ind_haplogroup population file, #注意空格飞Tab分割
cat llumina_mtDNA_Filter.fam | awk 'BEGIN{FS=" ";OFS="\t";}{print $2,$1;}' > indpopnew
paste -d' '  <(tail --lines=+2  llumina_mtDNA_Filter_Beast_haplogrep_All_ind_haplonew) <(cat indpopnew |cut -d' ' -f1-) > llumina_mtDNA_Filter_Beast_haplogrepAll.Traits

cat  llumina_mtDNA_Filter_Beast_haplogrepAll.Traits | awk 'BEGIN{FS=" ";OFS="\t";}{print $1"_"$2, $4;}' >  llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popOld
sed 's/[\t ]\+/ /g' llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popOld >  llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll

#Generated ind pop in different level
cat llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_pop |perl -npe "s/^(.*? .*?_.*?)_.*/\1/" > llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_pop_Level2
cat llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll |perl -npe "s/^(.*? .*?)_.*/\1/" > llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll_Level1

#generated the Haplogroup Traits Matrix
cat llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll_Level1|perl -npe "s/ +/\t/g;"|cut -f2|sort |uniq|perl -npe "s/\n/,/"|perl -npe "s/$/\n/;s/^/,/" >tmp_pop.txt; cat <(cat tmp_pop.txt |perl -npe "s/^,//;s/,$//") <(cat llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll_Level1|perl -npe "s/ +/\t/g"|cut -f1,2|while read sample pop;do cat tmp_pop.txt|perl -npe "s/,$pop,/,#,/"|perl -npe "s/[^#,\n]+/0/g;s/#/1/;s/^,/$sample\t/;s/,$//" ;done) > llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll_Level1.Traits

#generated the Traits template
trait_num=`head -n 1 llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll_Level1.Traits|perl -npe "s/,/\n/g"|wc -l `;trait_label=`head -n 1 llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll_Level1.Traits|perl -npe "s/,/, /g"`;matrix_value=`cat llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll_Level1.Traits|tail --lines=+2`;cat /home/biosoftware/ppgv1/popart/pop_Trait_template |perl -npe "s/trait_label/$trait_label/;s/matrix_value/$matrix_value/;s/trait_num/$trait_num/"  > llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll_Level1.Traits.Matrix

#Generated the final version for popART analysis
cat llumina_mtDNA_Filter_Beast_haplogrep_Label.nexus llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll_Level1.Traits.Matrix > llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popAll_Level1.Traits.Matrix.nexus




使用ID_Haplogroup联合标记ID作为分析的新标记,单倍群只保留两级
#Run Beast with two files allingment
cat llumina_mtDNA_Filterlineage2_phylotree17 |perl -npe "s/\"//g;s/ +/\t/g"|tail --lines=+2 >tmp.txt;cat llumina_mtDNA_Filter.fam|while read pop sample info; do new_name=`grep "^$sample"$'\t' tmp.txt |cut -f2`;echo  $sample$'\t'$new_name;done > ind_Haplogroup_sort

len=2;cat ind_Haplogroup_sort|perl -npe "s/$/\t$len/"|perl -F'\t' -alne '$F[1]=~s/(.{$F[2]}).*/\1/;print "$F[0]\t$F[1]";'> llumina_mtDNA_Filter_indHaplogroup2

cp llumina_mtDNA_Filter_indHaplogroup2 llumina_mtDNA_Filter_indCombinedHaplogroup2
sed -i "1iSampleID\tHaplogroup" llumina_mtDNA_Filter_indCombinedHaplogroup2
paste -d' '  <(cat llumina_mtDNA_Filter_recode.ped|cut -d' ' -f1-2|while read pop sample;do grep "^$pop"$'\t' llumina_mtDNA_Filter_indCombinedHaplogroup2;done ) <(cat llumina_mtDNA_Filter_recode.ped |cut -d' ' -f3-) |perl -npe "s/\t/_/"|cut -d' ' -f1,6-|perl -npe "s/^/>/;s/ ([ATCG]){2}/ \1/g;s/ 00/ N/g"|perl -npe  "s/ /\t/;s/ //g;"|perl -npe "s/.*\t\?+$//"|grep -v "^$"|perl -npe "s/\t/\n/" > llumina_mtDNA_Filter_Beast_haplogrep_LabelLevel2.fasta 

#Generate nexus files 生成nexus文件
python /home/biosoftware/vcf2phylip/fasta_nexus_converter/fasta_to_nexus/Main.py  llumina_mtDNA_Filter_Beast_haplogrep_LabelLevel2.fasta  
mv example.nex  llumina_mtDNA_Filter_Beast_haplogrep_LabelLevel2.nexus

#Generate ind_haplogroup population file, #注意空格飞Tab分割
cat llumina_mtDNA_Filter.fam | awk 'BEGIN{FS=" ";OFS="\t";}{print $2,$1;}' > indpopnew
paste -d' '  <(tail --lines=+2  llumina_mtDNA_Filter_indCombinedHaplogroup2) <(cat indpopnew |cut -d' ' -f1-) > llumina_mtDNA_Filter_Beast_haplogrep.Traits
cat  llumina_mtDNA_Filter_Beast_haplogrep.Traits | awk 'BEGIN{FS=" ";OFS="\t";}{print $1"_"$2, $4;}' >  llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popOld
sed 's/[\t ]\+/ /g' llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popOld >  llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_pop
rm llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_popOld

#Generated ind pop in different level
cat llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_pop |perl -npe "s/^(.*? .*?_.*?)_.*/\1/" > llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_pop_Level2
cat llumina_mtDNA_Filter_Beast_haplogrep_ind_Haplo_pop |perl -npe "s/^(.*? .*?)_.*/\1/" > llumina_mtDNA_Filter_Beast_haplogrep_ind_HaploGROUP2_pop_Level1

#generated the Haplogroup Traits Matrix
cat llumina_mtDNA_Filter_Beast_haplogrep_ind_HaploGROUP2_pop_Level1|perl -npe "s/ +/\t/g;"|cut -f2|sort |uniq|perl -npe "s/\n/,/"|perl -npe "s/$/\n/;s/^/,/" >tmp_pop.txt; cat <(cat tmp_pop.txt |perl -npe "s/^,//;s/,$//") <(cat llumina_mtDNA_Filter_Beast_haplogrep_ind_HaploGROUP2_pop_Level1|perl -npe "s/ +/\t/g"|cut -f1,2|while read sample pop;do cat tmp_pop.txt|perl -npe "s/,$pop,/,#,/"|perl -npe "s/[^#,\n]+/0/g;s/#/1/;s/^,/$sample\t/;s/,$//" ;done) > llumina_mtDNA_Filter_Beast_haplogrep_ind_HaploGROUP2_pop_Level1.Traits

#generated the Traits template
trait_num=`head -n 1 llumina_mtDNA_Filter_Beast_haplogrep_ind_HaploGROUP2_pop_Level1.Traits|perl -npe "s/,/\n/g"|wc -l `;trait_label=`head -n 1 llumina_mtDNA_Filter_Beast_haplogrep_ind_HaploGROUP2_pop_Level1.Traits|perl -npe "s/,/, /g"`;matrix_value=`cat llumina_mtDNA_Filter_Beast_haplogrep_ind_HaploGROUP2_pop_Level1.Traits|tail --lines=+2`;cat /home/biosoftware/ppgv1/popart/pop_Trait_template |perl -npe "s/trait_label/$trait_label/;s/matrix_value/$matrix_value/;s/trait_num/$trait_num/"  > llumina_mtDNA_Filter_Beast_haplogrep_ind_HaploGROUP2_pop_Level1.Traits.Matrix

#Generated the final version for popART analysis
cat llumina_mtDNA_Filter_Beast_haplogrep_LabelLevel2.nexus llumina_mtDNA_Filter_Beast_haplogrep_ind_HaploGROUP2_pop_Level1.Traits.Matrix > llumina_mtDNA_Filter_Beast_haplogrep_ind_HaploGROUP2_pop_Level1.Traits.Matrix.nexus

