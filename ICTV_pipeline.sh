#!/bin/bash

########################## ICTV Pipeline ########################################
# This script is written by Sejal Modha											#
#																				#
# This script can be used to download sequences from NCBI						#
# and process them through this pipeline and produce a raxML tree as output		#
#-------------------------------------------------------------------------------#
# This script is hardcoded to 													#
#	* Use a number of scripts including 										#
#		* DownloadProteinForTaxid.pl											#
#		* SanityCheck.pl														#
#		* BlastParseToList.pl													#
#		* CompileSequences.pl													#
#	  	* remove_subseq.pl														#
#																				#
# Usage:																		#
#	./ICTV_pipeline <options>													#
#	 OPTIONS:																	#
#		-t Taxa ID (Required)
#		-s Seed Set - Fasta (Required)
#		-l Hit Length for BLAST (Required)
#		-c Coverage for BLAST (Required)
#		-h Print usage help message (Optional)									#
#		-m Specify model for RAxML (Default is PTRGAMMJTT)
#-------------------------------------------------------------------------------#

usage=`echo -e "\n Usage: ICTV_pipeline <OPTIONS> \n\n
		-t Taxa ID - INT(Required) \n 
		-s Seedset in fasta format (Required) \n
		-l Hit Length for BLAST - INT(Required) \n
		-c Coverage for BLAST -INT(Required) \n
		-h This helpful message\n
		-m Specify model for RAxML (Default is PTRGAMMJTT)\n
		-p Number of threads"`;

if [[ ! $1 ]] 
then
	printf "${usage}\n\n";
exit;
fi

alpha='[a-zA-Z]';
raxml='PROTGAMMAJTT';
threads='2';
while getopts t:s:l:c:m:p:h flag; do
  case $flag in

    t)
	taxid=`echo "$OPTARG"`;
	
	if [[ $taxid =~ .*$alpha.* ]]
    then
		printf "\n!!!! Invalid Taxa ID: Please enter a valid Taxa ID !!!! \nExample: 40120\n";
		exit 1;
	else
		tid=`echo txid$taxid`;
		if [ ! -d "$tid" ]; then
			mkdir $tid;
		fi
		printf "\nTaxaID validated \n\nRunning pipeline with following parameters:\n\nTaxa ID\t\t: $tid \n";	
    fi

	;;
    s)
	seeds=`echo "$OPTARG"`;
	
	if [[ ! -f $seeds ]]
	then
		printf "\nSpecified seeds file $seeds file does not exist \n \n";
		exit 1;
	else
		printf "Seed set\t: $seeds \n";
	fi
	#echo $seeds;
	;; 
    l)
	len=`echo "$OPTARG"`;
	
	if [[ $len =~ .*$alpha.* ]]
    then
		printf "\n!!!! Invalid Length: Please enter a valid length value !!!! \n";
		exit 1;
	else
		printf "BLAST length\t: $len \n";	
    fi
	;;
    c)
	cover=`echo "$OPTARG"`;
	
	if [[ $cover =~ .*$alpha.* ]]
    then
		printf "\n!!!! Invalid Coverage Value: Please enter a valid coverage value !!!! \n";
		exit 1;
	else
		printf "BLAST coverage\t: $cover \n";
    fi	
	;;
    m)
	raxModel=`echo "$OPTARG"`;
	
	if [[ -z $raxModel ]]
	then
		raxModel=$raxml;
		printf "Selecting default RAxML model PROTGAMMAJTT \n";
	else
		raxml=$raxModel;
		printf "RAxML model set to $raxModel \n";
	fi	
	;;
	p)
	proc=`echo "$OPTARG"`;
	
	if [[ $proc =~ .*$alpha.* ]]
    then
		printf "\n!!!! Invalid Number of Threads: Please enter a valid number of threads !!!! \n";
		exit 1;
	elif [[ -z $proc ]]
	then
		proc=$threads;
		printf "Default threads $threads \n";
	else
		printf "No of threads\t: $proc \n"; 	
    fi
	;;
	
    h)
     	printf "${usage}\n\n";
	;;
    \?)
	echo -e "\n Option you selected doesn't exist \n Please use -h flag for usage";
	exit;
      ;;
  esac
done

#Processing begins here
printf "\nNow Downloading all protein sequences from NCBI for taxid $tid \n";
echo "-----------------Running Step 1 of Pipeline --------------------";
#perl DownloadProteinForTaxid.pl $tid/$tid.fa $tid;
echo  "Downloading sequences from NCBI"
esearch -db taxonomy -query "$tid[Organism]"|elink -target protein|efetch -format fasta > $tid/$tid.fa
echo "-----------------Running Step 2 of Pipeline --------------------";

printf "Sequences downloaded successfully now running sanity check on them\n";
perl SanityCheck.pl $tid/$tid.fa $tid/${tid}_checked.fa;
# re-format sequences to suit newer version of NCBI fasta headers
sed -i 's/gi|[0-9]*|[a-z]*|//g;s/|//;s/\.[1-9].*//g' $tid/${tid}_checked.fa

echo "-----------------Running Step 3 of Pipeline --------------------";	
printf "Creating BLAST databases\n";
	
formatdb -i $tid/${tid}_checked.fa -p T

echo "-----------------Running Step 4 of Pipeline --------------------";
printf "Running BLASTP \n";

blastall -p blastp -i $seeds -d $tid/${tid}_checked.fa -o $tid/${tid}_blastp.txt -e 1 -v 1000000 -b 1000000

echo "-----------------Running Step 5 of Pipeline --------------------";
printf "Compiling Sequences \n";

perl BlastParseToList.pl -inblast $tid/${tid}_blastp.txt -out $tid/${tid}_filtered.txt -hit_length $len -cover $cover;
grep --no-group-separator -A 1 -f $tid/${tid}_filtered.txt <(awk -v ORS= '/^>/ { $0 = (NR==1 ? "" : RS) $0 RS } END { printf RS }1' $tid/${tid}_checked.fa) >$tid/${tid}_set.fa
#perl CompileSequences.pl $tid/${tid}_checked.fa $tid/${tid}_filtered.txt $tid/${tid}_set > /dev/null 2>&1;
echo "Gathering metadata";
#bash CollectSequenceInfo.sh -i ${tid}/${tid}_set_table.txt -o ${tid}
bash CollectMetadata.sh $tid/${tid}_filtered.txt ${tid}/${tid}_label.csv

#if [[ -e ${tid}_metadata ]] 
#	then
#		mv ${tid}_metadata ${tid}/${tid}_label.csv 
#else 
#	printf "${tid}_metadata does not exist." 
#	exit 1;
#fi

#combine seeds and blast sets
cat $tid/${tid}_set.fa $seeds > $tid/${tid}_set_seeds_combined.fa;
echo "Removing Exact Duplicates";
	
## Truncate seq ID in fasta file 
perl -p -i -e 's/>(.+?) .+/>$1/g' $tid/${tid}_set_seeds_combined.fa
# Sort and group exact same sequences in a table and sort gi to generate a fasta with oldest gi as description and sequence
awk 'BEGIN{RS=">"}NR>1{sub("\n","\t"); gsub("\n",""); print $0}' $tid/${tid}_set_seeds_combined.fa |sort -t $'\t' -f -k 2,2 -k 1,1n|awk -F'\t' -v OFS='\t' '{x=$2;$2="";a[x]=a[x]$0}END{for(x in a)print x,a[x]}' > ${tid}/${tid}_sequences_grouped
	
awk -F$'\t' '{print ">"$2"\n"$1}' ${tid}/${tid}_sequences_grouped >$tid/${tid}_combined_set_dups_removed.fa
perl -pe '/^>/ ? print "\n" : chomp' $tid/${tid}_combined_set_dups_removed.fa| tail -n +2 > $tid/${tid}_combined_set_dups_removed_formatted.fa
	
echo "Removing Shorter Sequences";
perl remove_subseq.pl $tid/${tid}_combined_set_dups_removed_formatted.fa $tid/${tid}_final_set.fa;

#Throw a warning message for the sequences for which metadata was not found
#TODO

echo "-----------------Running Step 6 of Pipeline --------------------";
printf "Grouping identical sequences \n"; 

perl -pe '/^>/ ? print "\n" : chomp' $tid/${tid}_set_seeds_combined.fa |tail -n +2|paste -d "\t" - - |sed -e 's/>//g' |awk -v OFS='\t' -F "\t" '{t=$1; $1=$2; $2=t; print}' | sort | awk -F "\t" '{if($1==seq) {printf("\t%s",$2)} else { printf("\n%s",$0); seq=$1;}};END{printf "\n"}' > seq_id_grouped
awk 'BEGIN{RS=">"}NR>1{sub("\n","\t"); gsub("\n",""); print $0}' $tid/${tid}_final_set.fa | cut -f1 > file_with_id_list
bash find_ids.sh file_with_id_list seq_id_grouped |  sed  -e '1iRepresentative_GI\tProtein_Sequence\tExtended_GI_List' > $tid/${tid}_seq_info 


echo "-----------------Running Step 7 of Pipeline --------------------";
printf "Running Multiple Sequence Alignments Using CLUSTALO \n"; 
clustalo -i $tid/${tid}_final_set.fa -o $tid/${tid}_final_set_clustalo_aln.phy --outfmt="phy" --force --full --distmat-out=$tid/${tid}_clustalo_dist_mat
#Format matrix file for visualization
sed -e '1d' $tid/${tid}_clustalo_dist_mat| tr -s " "| sed 's/ /,/g' > $tid/${tid}.csv
header=`cut -f1 -d ',' $tid/${tid}.csv| tr '\n' ','|sed 's/,$//g'`
sed -i "1ispecies,"$header"" $tid/${tid}.csv 

rm file_with_id_list seq_id_grouped $tid/${tid}_set_seeds_combined.fa $tid/${tid}_set.fa $tid/${tid}_combined_set_dups_removed_formatted.fa  $tid/${tid}_blastp.txt #$tid/${tid}_checked.fa* 


echo "-----------------Running Step 8 of Pipeline --------------------";
printf "Running Phylogenetic Analysis using RAXML \n";
printf "RAxML model is set to $raxml \n\n";
cd $tid;
printf "raxmlHPC-PTHREADS -f a -m $raxml -p 12345 -x 12345 -# 100 -s ${tid}_final_set_clustalo_aln.phy -n $tid -T $proc \n";
raxmlHPC-PTHREADS -f a -m $raxml -p 12345 -x 12345 -# 100 -s ${tid}_final_set_clustalo_aln.phy -n $tid -T $proc

#Reroot the tree
raxmlHPC-PTHREADS -f I -t RAxML_bipartitionsBranchLabels.$tid -m PROTGAMMAJTT -n ${tid}_reroot	
if [[ -e RAxML_rootedTree.${tid}_reroot ]] 
then
	mv RAxML_rootedTree.${tid}_reroot ${tid}.nhx
else
	printf "RAxML_rootedTree.${tid}_reroot does not exist";
	exit 1;
fi
cd ..

cp ${tid}/${tid}.nhx ${tid}/${tid}_label.csv ${tid}/${tid}.csv phylotree/data/

git add $tid
git commit -m "Pipeline updated for $tid"
git push
cd phylotree
git add data/${tid}.nhx data/${tid}.csv	data/${tid}_label.csv
git commit -m "Data files updated for $tid"
git push