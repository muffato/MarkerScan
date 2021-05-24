"""
Pipeline to detect contaminants in Hifi reads
----------------------------------------------------
Requirements 
 - Conda (https://conda.io/docs/commands/conda-install.html)
 - SnakeMake (http://snakemake.readthedocs.io/en/stable/)
Basic usage:
  snakemake -p --use-conda --conda-prefix condadir --configfile config.yaml
"""
scriptdir = config["scriptdir"]
reads = config["reads"]
datadir = config["datadir"]
#envsdir = config["envsdir"]
sciname_goi = config["sci_name"]
SSUHMMfile = config["SSUHMMfile"]
genome = config["genome"]
datasets = config["datasets"]
microsporidiadb = config["microsporidiadb"]

rule all:
	input:
		expand("{pwd}/{name}.ProkSSU.reduced.fa",pwd=config["workingdirectory"], name=config["shortname"]),
		expand("{pwd}/{name}.ProkSSU.reduced.SILVA.genus.txt",pwd=config["workingdirectory"], name=config["shortname"]),		
		expand("{pwd}/kraken.tax.masked.ffn",pwd=config["workingdirectory"]),
		expand("{pwd}/kraken.report",pwd=config["workingdirectory"]),
		expand("{pwd}/final_assembly.fa",pwd=config["workingdirectory"]),
		expand("{pwd}/final_reads_removal.fa",pwd=config["workingdirectory"]),
		expand("{pwd}/final_reads_target.fa.gz",pwd=config["workingdirectory"]),
		expand("{pwd}/putative_reads_removal.fa",pwd=config["workingdirectory"]),
		expand("{pwd}/{name}.report.pdf",pwd=config["workingdirectory"], name=config["shortname"])

rule HMMscan_SSU:
	"""
	Run HMMscan with prokaryotic+viral HMM (RF00177+RF01959)
	"""
	output:
		dom = "{workingdirectory}/{shortname}.ProkSSU.domout", 
		log = "{workingdirectory}/{shortname}.HMMscan.log"
	threads: 10
	conda: "envs/hmmer.yaml"
	shell:
		"""
		nhmmer --cpu {threads} --noali --tblout {output.dom} -o {output.log} {SSUHMMfile} {genome}
		"""

rule FetchHMMReads:
	"""
	Fetch detected reads with prokaryotic 16S signature
	"""
	input:
		dom = "{workingdirectory}/{shortname}.ProkSSU.domout"
	output:
		readsinfo = "{workingdirectory}/{shortname}.ProkSSU.readsinfo",
		readsinfomicro = "{workingdirectory}/{shortname}.ProkSSU.microsporidia.readsinfo",
		readslist = "{workingdirectory}/{shortname}.ProkSSU.readslist",
		readslistmicro = "{workingdirectory}/{shortname}.ProkSSU.microsporidia.readslist"
	shell:
		"""
		python {scriptdir}/GetReadsSSU_nhmmer.py -i {input.dom} | grep -v 'RF02542.afa' > {output.readsinfo} || true
		python {scriptdir}/GetReadsSSU_nhmmer.py -i {input.dom} | grep 'RF02542.afa' > {output.readsinfomicro} || true
		cut -f1 {output.readsinfo} > {output.readslist}
		cut -f1 {output.readsinfomicro} > {output.readslistmicro}
		"""

rule Fetch16SLoci:
	"""
	Get fasta sequences for detected reads with prokaryotic 16S signature and extract 16S locus
	"""
	input:
		readslist = "{workingdirectory}/{shortname}.ProkSSU.readslist",
		readsinfo = "{workingdirectory}/{shortname}.ProkSSU.readsinfo",
		readsinfomicro = "{workingdirectory}/{shortname}.ProkSSU.microsporidia.readsinfo",
		readslistmicro = "{workingdirectory}/{shortname}.ProkSSU.microsporidia.readslist"
	output:
		fasta16S = "{workingdirectory}/{shortname}.ProkSSU.reads.fa",
		fasta16SLoci = "{workingdirectory}/{shortname}.ProkSSU.fa",
		fasta16SLociReduced = "{workingdirectory}/{shortname}.ProkSSU.reduced.fa",
		fasta16Smicro = "{workingdirectory}/{shortname}.ProkSSU.reads.microsporidia.fa",
		fasta16SLocimicro = "{workingdirectory}/{shortname}.ProkSSU.microsporidia.fa",
		fasta16SLociReducedmicro = "{workingdirectory}/{shortname}.ProkSSU.microsporidia.reduced.fa"
	log: "{workingdirectory}/{shortname}.cdhit.log"
	conda:	"envs/cdhit.yaml"
	shell:
		"""
		seqtk subseq {genome} {input.readslist} > {output.fasta16S}
		python {scriptdir}/FetchSSUReads.py -i {input.readsinfo} -f {output.fasta16S} -o {output.fasta16SLoci}
		cd-hit-est -i {output.fasta16SLoci} -o {output.fasta16SLociReduced} -c 0.99 -T 1 -G 0 -aS 1 2> {log}
		if [ -s {input.readslistmicro} ]; then
			seqtk subseq {genome} {input.readslistmicro} > {output.fasta16Smicro}
			python {scriptdir}/FetchSSUReads.py -i {input.readsinfomicro} -f {output.fasta16Smicro} -o {output.fasta16SLocimicro}
			cd-hit-est -i {output.fasta16SLocimicro} -o {output.fasta16SLociReducedmicro} -c 0.99 -T 1 -G 0 -aS 1 2> {log}
		else
			touch {output.fasta16Smicro}
			touch {output.fasta16SLocimicro}
			touch {output.fasta16SLociReducedmicro}
		fi
		"""

rule DownloadSILVA:
	"""
	Download latest release SILVA DB
	"""
	output:
		donesilva = "{workingdirectory}/silva_download.done.txt"
	shell:
		"""
		var=$(curl -L https://ftp.arb-silva.de/current/ARB_files/ | grep 'SSURef_opt.arb.gz.md5' | cut -f2 -d '\"')
		curl -R https://ftp.arb-silva.de/current/ARB_files/$var --output {datadir}/silva/$var
		filename=$(basename $var .md5)
		filenameshort=$(basename $filename .gz)
		if [ -f {datadir}/silva/SILVA_SSURef.arb ]; then
			if [ {datadir}/silva/$var -nt {datadir}/silva/SILVA_SSURef.arb ]; then
				curl -R https://ftp.arb-silva.de/current/ARB_files/$filename --output {datadir}/silva/$filename
				gunzip {datadir}/silva/$filename
				mv {datadir}/silva/$filenameshort {datadir}/silva/SILVA_SSURef.arb
			fi
		else
			curl -R https://ftp.arb-silva.de/current/ARB_files/$filename --output {datadir}/silva/$filename
			gunzip {datadir}/silva/$filename
			mv {datadir}/silva/$filenameshort {datadir}/silva/SILVA_SSURef.arb
		fi
		touch {output.donesilva}
		"""

rule DownloadOrganelles:
	"""
	Download gff flatfiles and fna of plastid and mitochondria from ftp release NCBI
	"""
	input:
		taxnames = expand("{datadir}/taxonomy/names.dmp",datadir=config["datadir"])
	output:
		doneorganelles = "{workingdirectory}/organelles_download.done.txt"
	conda:	"envs/cdhit.yaml"
	shell:
		"""
		if [ ! -d {datadir}/organelles ]; then
  			mkdir {datadir}/organelles
		fi
		if [ -s {datadir}/organelles/organelles.lineage.txt ]; then
        	before=$(date -d 'today - 30 days' +%s)
        	timestamp=$(stat -c %y {datadir}/organelles/organelles.lineage.txt | cut -f1 -d ' ')
        	timestampdate=$(date -d $timestamp +%s)
        	if [ $before -ge $timestampdate ]; then
                rm {datadir}/organelles/*
				mt=$(curl -L https://ftp.ncbi.nlm.nih.gov/refseq/release/mitochondrion/ | grep -E 'genomic.gbff|genomic.fna' | cut -f2 -d '\"')
				pt=$(curl -L https://ftp.ncbi.nlm.nih.gov/refseq/release/plastid/ | grep -E 'genomic.gbff|genomic.fna' | cut -f2 -d '\"')
				for file in $mt;
				do
					curl -R https://ftp.ncbi.nlm.nih.gov/refseq/release/mitochondrion/$file --output {datadir}/organelles/$file
				done
				for file in $pt;
				do
					curl -R https://ftp.ncbi.nlm.nih.gov/refseq/release/plastid/$file  --output {datadir}/organelles/$file
				done
				python {scriptdir}/OrganelleLineage.py -d {datadir}/organelles/ -na {input.taxnames} -o {datadir}/organelles/organelles.lineage.txt
				cat {datadir}/organelles/*genomic.fna.gz | gunzip > {datadir}/organelles/organelles.fna
				rm {datadir}/organelles/*genomic.fna.gz
				rm {datadir}/organelles/*gbff.gz
			fi
		else
			mt=$(curl -L https://ftp.ncbi.nlm.nih.gov/refseq/release/mitochondrion/ | grep -E 'genomic.gbff|genomic.fna' | cut -f2 -d '\"')
			pt=$(curl -L https://ftp.ncbi.nlm.nih.gov/refseq/release/plastid/ | grep -E 'genomic.gbff|genomic.fna' | cut -f2 -d '\"')
			for file in $mt;
			do
				curl -R https://ftp.ncbi.nlm.nih.gov/refseq/release/mitochondrion/$file --output {datadir}/organelles/$file
			done
			for file in $pt;
			do
				curl -R https://ftp.ncbi.nlm.nih.gov/refseq/release/plastid/$file  --output {datadir}/organelles/$file
			done
			python {scriptdir}/OrganelleLineage.py -d {datadir}/organelles/ -na {input.taxnames} -o {datadir}/organelles/organelles.lineage.txt
			cat {datadir}/organelles/*genomic.fna.gz | gunzip > {datadir}/organelles/organelles.fna
			rm {datadir}/organelles/*genomic.fna.gz
			rm {datadir}/organelles/*gbff.gz
		fi	
		touch {output.doneorganelles}
		"""

rule DownloadApicomplexa:
	"""
	Download gff flatfiles and fna of plastid and mitochondria from ftp release NCBI
	"""
	input:
		taxnames = expand("{datadir}/taxonomy/names.dmp",datadir=config["datadir"])
	output:
		done_api = "{workingdirectory}/apicomplexa_download.done.txt"
	conda:	"envs/eutils.yaml"
	shell:
		"""
		if [ ! -d {datadir}/apicomplexa ]; then
  			mkdir {datadir}/apicomplexa
		fi
		if [ -s {datadir}/apicomplexa/apicomplexa.lineage.ffn ]; then
        	before=$(date -d 'today - 30 days' +%s)
        	timestamp=$(stat -c %y {datadir}/apicomplexa/apicomplexa.lineage.ffn | cut -f1 -d ' ')
        	timestampdate=$(date -d $timestamp +%s)
        	if [ $before -ge $timestampdate ]; then
                rm {datadir}/apicomplexa/*
				esearch -db nucleotide -query "apicoplast[Title] complete genome[Title] txid5794 [Organism]" | efilter -source insd | efetch -format fasta > {datadir}/apicomplexa/apicoplast.fasta
				esearch -db nucleotide -query "mitochondrion[Title] complete genome[Title] txid5794 [Organism]" | efilter -source insd | efetch -format fasta > {datadir}/apicomplexa/mito.fasta
				python {scriptdir}/ApicomplexaLineage.py -d {datadir}/apicomplexa/ -na {input.taxnames} -o {datadir}/apicomplexa/apicomplexa.lineage.ffn
			fi
		else
			esearch -db nucleotide -query "apicoplast[Title] complete genome[Title] txid5794 [Organism]" | efilter -source insd | efetch -format fasta > {datadir}/apicomplexa/apicoplast.fasta
			esearch -db nucleotide -query "mitochondrion[Title] complete genome[Title] txid5794 [Organism]" | efilter -source insd | efetch -format fasta > {datadir}/apicomplexa/mito.fasta
			python {scriptdir}/ApicomplexaLineage.py -d {datadir}/apicomplexa/ -na {input.taxnames} -o {datadir}/apicomplexa/apicomplexa.lineage.ffn
		fi	
		touch {output.done_api}
		"""

rule DownloadNCBITaxonomy:
	"""
	Download current version of NCBI taxonomy
	"""
	input:
		taxdir = directory(expand("{datadir}/taxonomy/",datadir=config["datadir"])),
	output:
		#taxnames = "{datadir}/taxonomy/names.dmp",
		#taxnodes = "{datadir}/taxonomy/nodes.dmp",
		#accessionfile = "{datadir}/taxonomy/nucl_gb.accession2taxid",
		donefile = "{workingdirectory}/taxdownload.done.txt"
	shell:
		"""
		curl -R ftp://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz.md5 --output {input.taxdir}/taxdump.tar.gz.md5
		if [ -f {input.taxdir}/names.dmp ]; then
			if [ {input.taxdir}/taxdump.tar.gz.md5 -nt {input.taxdir}/names.dmp ]; then
				curl -R ftp://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz --output taxdump.tar.gz
				tar -xvf taxdump.tar.gz
				mv names.dmp {input.taxdir}/names.dmp
				mv nodes.dmp {input.taxdir}/nodes.dmp
				rm division.dmp gencode.dmp citations.dmp delnodes.dmp merged.dmp readme.txt gc.prt taxdump.*
			fi
		else
			curl -R ftp://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz --output taxdump.tar.gz
			tar -xvf taxdump.tar.gz
			mv names.dmp {input.taxdir}/names.dmp
			mv nodes.dmp {input.taxdir}/nodes.dmp
			rm division.dmp gencode.dmp citations.dmp delnodes.dmp merged.dmp readme.txt gc.prt taxdump.*
		fi
		curl -R ftp.ncbi.nih.gov/pub/taxonomy/accession2taxid/nucl_gb.accession2taxid.gz.md5 --output nucl_gb.accession2taxid.gz.md5
		if [ -f {input.taxdir}/nucl_gb.accession2taxid ]; then
			if [ nucl_gb.accession2taxid.gz.md5 -nt {input.taxdir}/nucl_gb.accession2taxid.gz.md5 ]; then
				mv nucl_gb.accession2taxid.gz.md5 {input.taxdir}/nucl_gb.accession2taxid.gz.md5
				curl -R ftp.ncbi.nih.gov/pub/taxonomy/accession2taxid/nucl_gb.accession2taxid.gz --output nucl_gb.accession2taxid.gz
				curl -R ftp.ncbi.nih.gov/pub/taxonomy/accession2taxid/nucl_wgs.accession2taxid.gz --output nucl_wgs.accession2taxid.gz
				gunzip nucl_gb.accession2taxid.gz nucl_wgs.accession2taxid.gz
				mv nucl_wgs.accession2taxid {input.taxdir}/nucl_wgs.accession2taxid
				mv nucl_gb.accession2taxid {input.taxdir}/nucl_gb.accession2taxid
			else
				rm nucl_gb.accession2taxid.gz.md5
			fi
		else
			curl -R ftp.ncbi.nih.gov/pub/taxonomy/accession2taxid/nucl_gb.accession2taxid.gz --output nucl_gb.accession2taxid.gz
			curl -R ftp.ncbi.nih.gov/pub/taxonomy/accession2taxid/nucl_wgs.accession2taxid.gz --output nucl_wgs.accession2taxid.gz
			gunzip nucl_gb.accession2taxid.gz nucl_wgs.accession2taxid.gz
			mv nucl_wgs.accession2taxid {input.taxdir}/nucl_wgs.accession2taxid
			mv nucl_gb.accession2taxid {input.taxdir}/nucl_gb.accession2taxid			
		fi
		touch {output.donefile}
		"""

rule ClassifySSU:
	"""
	Classify all extracted (and reduced) 16S loci using SILVA DB to determine genera present
	"""
	input:
		fasta16SLociReduced = "{workingdirectory}/{shortname}.ProkSSU.reduced.fa",
		fasta16SLociReducedmicro = "{workingdirectory}/{shortname}.ProkSSU.microsporidia.reduced.fa",
		taxnames = expand("{datadir}/taxonomy/names.dmp",datadir=config["datadir"]),
		taxnodes = expand("{datadir}/taxonomy/nodes.dmp",datadir=config["datadir"]),
		donesilva = "{workingdirectory}/silva_download.done.txt"
	output:
		SILVA_output_embl = "{workingdirectory}/{shortname}.ProkSSU.reduced.SILVA.embl.csv",
		SILVA_output_silva = "{workingdirectory}/{shortname}.ProkSSU.reduced.SILVA.silva.csv",
		SILVA_output = "{workingdirectory}/{shortname}.ProkSSU.reduced.SILVA.csv",
		SILVA_tax = "{workingdirectory}/{shortname}.ProkSSU.reduced.SILVA.tax",
		blastout = "{workingdirectory}/{shortname}.ProkSSU.reduced.microsporidia.blast.txt",
		blastgenus = "{workingdirectory}/{shortname}.ProkSSU.reduced.microsporidia.genus.txt",
		SILVA16Sgenus = "{workingdirectory}/{shortname}.ProkSSU.reduced.SILVA.genus.txt"
	conda: "envs/sina.yaml"
	threads: 10
	shell:
		"""
		sina -i {input.fasta16SLociReduced} -o {output.SILVA_output_embl} --db {datadir}/silva/SILVA_SSURef.arb --search --search-min-sim 0.9 -p {threads} --lca-fields tax_embl_ebi_ena --outtype csv
		sina -i {input.fasta16SLociReduced} -o {output.SILVA_output_silva} --db {datadir}/silva/SILVA_SSURef.arb --search --search-min-sim 0.9 -p {threads} --lca-fields tax_slv --outtype csv
		cat {output.SILVA_output_embl} {output.SILVA_output_silva} > {output.SILVA_output}
		cut -f1,8 -d',' {output.SILVA_output} | tr ',' '\t' > {output.SILVA_tax}
		cut -f2 {output.SILVA_tax} | grep -v 'lca_tax_embl_ebi_ena' | grep -v 'lca_tax_slv' | sort | uniq > {output.SILVA16Sgenus} && [[ -s {output.SILVA16Sgenus} ]]
		if [ -s {input.fasta16SLociReducedmicro} ]; then
			blastn -db {microsporidiadb} -query {input.fasta16SLociReducedmicro} -out {output.blastout} -outfmt 6
			python {scriptdir}/ParseBlastLineage.py -b {output.blastout} -na {input.taxnames} -no {input.taxnodes} > {output.blastgenus}
			cat {output.blastgenus} >> {output.SILVA16Sgenus}
		else
			touch {output.blastout}
			touch {output.blastgenus}
		fi
		"""

rule MapAllReads2Assembly:
	output:
		paffile = "{workingdirectory}/AllReadsGenome.paf",
		mapping = "{workingdirectory}/AllReadsGenome.ctgs",
		reads = "{workingdirectory}/AllReadsGenome.reads",
	threads: 10
	conda: "envs/minimap.yaml"
	shell:
		"""
		minimap2 -x map-pb -t {threads} {genome} {reads}  > {output.paffile}
		python {scriptdir}/PafAlignment.py -p {output.paffile} -o {output.mapping} -r {output.reads}
		"""

checkpoint GetGenera:
	"""
	Get genera which were detected in SILVA DB 16 screen
	"""
	input:
		#SILVA16Sgenus = "{workingdirectory}/{shortname}.ProkSSU.reduced.SILVA.genus.txt"
		SILVA16Sgenus = expand("{pwd}/{name}.ProkSSU.reduced.SILVA.genus.txt",pwd=config["workingdirectory"], name=config["shortname"]),
		#screenfile = "{workingdirectory}/refseq202.screen",
		#asminfo = expand("{datadir}/mash/assembly_summary_refseq.txt",datadir=config["datadir"]),
		taxnames = expand("{datadir}/taxonomy/names.dmp",datadir=config["datadir"]),
		taxnodes = expand("{datadir}/taxonomy/nodes.dmp",datadir=config["datadir"])
	output:
		generadir = directory("{workingdirectory}/genera")
	shell:
		"""
		mkdir {output.generadir}
		python {scriptdir}/DetermineGenera.py -i {input.SILVA16Sgenus} -t family -na {input.taxnames} -no {input.taxnodes} -od {output} -suf SSU.genera_taxonomy.txt -g '{sciname_goi}'
		while read p
		do
			shortname=`echo $p | cut -d, -f1`	
			echo $p > {output.generadir}/genus.$shortname.txt
		done < {output.generadir}/euk.SSU.genera_taxonomy.txt
		while read p
		do
			echo "Bacteria/Archaea" > {output.generadir}/genus.$p.txt
			#touch  {output.generadir}/genus.$p.txt
		done < {output.generadir}/prok.SSU.genera_taxonomy.txt
		rm {output.generadir}/euk.SSU.genera_taxonomy.txt
		rm {output.generadir}/prok.SSU.genera_taxonomy.txt
		"""

rule DownloadRefSeqGenus:
	"""
	Download RefSeq genomes (per species) of selected genera from 16S screen
	"""
	input:
		generafiles = "{workingdirectory}/genera/genus.{genus}.txt",
		doneorganelles = "{workingdirectory}/organelles_download.done.txt",
		done_api = "{workingdirectory}/apicomplexa_download.done.txt"
	params:
		taxname = "{genus}"
	output:
		#novel_pwd = directory("{datadir}/genera/{genus}"),
		#refseqlog = "{datadir}/genera/{genus}/{genus}.refseq.log",
		#downloadlog = "{datadir}/genera/{genus}/{genus}.download.log",
		#refseqdir = directory("{datadir}/genera/{genus}/{genus}.Refseq"),
		#refseqdir_orig = temp("{datadir}/genera/{genus}/RefSeq.{genus}.zip"),
		krakenffnall = "{workingdirectory}/genera/{genus}.kraken.tax.ffn",
		orglist = "{workingdirectory}/genera/{genus}.organelles.list",
		orgfasta = "{workingdirectory}/genera/{genus}.organelles.ffn",
		apifile = "{workingdirectory}/genera/{genus}.additional.ffn",
		donefile = "{workingdirectory}/{genus}.refseqdownload.done.txt"
	shell:
		"""
		if [ ! -d {datadir}/genera ]; then
  			mkdir {datadir}/genera
		fi
		if [ -s {datadir}/genera/{params.taxname}.kraken.tax.ffn ]; then
			before=$(date -d 'today - 30 days' +%s)
			timestamp=$(stat -c %y {datadir}/genera/{params.taxname}.kraken.tax.ffn | cut -f1 -d ' ')
			timestampdate=$(date -d $timestamp +%s)
			if [ $before -ge $timestampdate ]; then
				if [ -d {datadir}/genera/{params.taxname} ]; then
					rm -r {datadir}/genera/{params.taxname}
				fi
				mkdir {datadir}/genera/{params.taxname}
				if grep -q Eukaryota {input.generafiles}; then
					python {scriptdir}/FetchGenomesRefSeq.py --refseq no --taxname {input.generafiles} --dir {datadir}/genera/{params.taxname} -d {datasets} > {datadir}/genera/{params.taxname}/{params.taxname}.refseq.log
				else
					python {scriptdir}/FetchGenomesRefSeq.py --refseq yes --taxname {input.generafiles} --dir {datadir}/genera/{params.taxname} -d {datasets} > {datadir}/genera/{params.taxname}/{params.taxname}.refseq.log
				fi
				if [ -s {datadir}/genera/{params.taxname}/{params.taxname}.refseq.log ]; then
					unzip -d {datadir}/genera/{params.taxname}/{params.taxname}.Refseq {datadir}/genera/{params.taxname}/RefSeq.{params.taxname}.zip
					python {scriptdir}/AddTaxIDKraken.py -d {datadir}/genera/{params.taxname}/{params.taxname}.Refseq -o {datadir}/genera/{params.taxname}.kraken.tax.ffn
				fi
			fi
		else
			if [ ! -d {datadir}/genera/{params.taxname} ]; then
				mkdir {datadir}/genera/{params.taxname}
			fi
			if grep -q Eukaryota {input.generafiles}; then
				python {scriptdir}/FetchGenomesRefSeq.py --refseq no --taxname {input.generafiles} --dir {datadir}/genera/{params.taxname} -d {datasets} > {datadir}/genera/{params.taxname}/{params.taxname}.refseq.log
			else
				python {scriptdir}/FetchGenomesRefSeq.py --refseq yes --taxname {input.generafiles} --dir {datadir}/genera/{params.taxname} -d {datasets} > {datadir}/genera/{params.taxname}/{params.taxname}.refseq.log
			fi
			if [ -s {datadir}/genera/{params.taxname}/{params.taxname}.refseq.log ]; then
				unzip -d {datadir}/genera/{params.taxname}/{params.taxname}.Refseq {datadir}/genera/{params.taxname}/RefSeq.{params.taxname}.zip
				python {scriptdir}/AddTaxIDKraken.py -d {datadir}/genera/{params.taxname}/{params.taxname}.Refseq -o {datadir}/genera/{params.taxname}.kraken.tax.ffn
			else
				touch {datadir}/genera/{params.taxname}.kraken.tax.ffn
			fi
		fi
		touch {output.apifile}
		if grep -q Eukaryota {input.generafiles}; then
			grep {params.taxname} {datadir}/organelles/organelles.lineage.txt > {output.orglist} || true
			python {scriptdir}/FastaSelect.py -f {datadir}/organelles/organelles.fna -l {output.orglist} -o {output.orgfasta}
			if grep -q Apicomplexa {input.generafiles}; then
				cp {datadir}/apicomplexa/apicomplexa.lineage.ffn {output.apifile}
			fi
		else
			touch {output.orglist}
			touch {output.orgfasta}
		fi
		cat {datadir}/genera/{params.taxname}.kraken.tax.ffn {output.orgfasta} {output.apifile} > {output.krakenffnall}
		touch {output.donefile}
		"""

def aggregate_kraken(wildcards):
	checkpoint_output=checkpoints.GetGenera.get(**wildcards).output[0]
	return expand ("{workingdirectory}/genera/{genus}.kraken.tax.ffn", workingdirectory=config["workingdirectory"], genus=glob_wildcards(os.path.join(checkpoint_output, 'genus.{genus}.txt')).genus)

rule concatenate_kraken_input:
	input:
		aggregate_kraken
	output:
		"{workingdirectory}/kraken.tax.ffn"
	shell:
		"""
		if [ -n "{input}" ]
		then
			cat {input} > {output}
		else
			touch {output}
		fi
		"""

rule DownloadGenusRel:
	"""
	Download assemblies of closely related species to species of interest
	"""
	input:
		taxnames = expand("{datadir}/taxonomy/names.dmp",datadir=config["datadir"]),
		taxnodes = expand("{datadir}/taxonomy/nodes.dmp",datadir=config["datadir"])
	output:
		novel_pwd = directory("{workingdirectory}/relatives/"),
		refseqlog = "{workingdirectory}/relatives/relatives.refseq.log",
		refseqdir = directory("{workingdirectory}/relatives/relatives.Refseq"),
		krakenffnrel = "{workingdirectory}/relatives/relatives.kraken.tax.ffn"
	conda: "envs/kraken.yaml"
	shell:
		"""
		if [ ! -d {datadir}/relatives ]; then
  			mkdir {datadir}/relatives
		fi
		python {scriptdir}/FetchGenomesRefSeqRelatives.py --taxname '{sciname_goi}' --dir {output.novel_pwd} --dir2 {datadir}/relatives -na {input.taxnames} -no {input.taxnodes} -o {output.refseqdir} -d {datasets} > {output.refseqlog}
		python {scriptdir}/AddTaxIDKraken.py -d {output.refseqdir} -o {output.krakenffnrel}
		"""

checkpoint SplitFasta:
	"""
	Split downloaded assemblies fasta file depending on the number of cores
	"""
	input:
		krakenffnall = "{workingdirectory}/kraken.tax.ffn"
	output:
		splitdir = directory("{workingdirectory}/split_fasta/")
	shell:
		"""
		python {scriptdir}/FastaSplit.py -f {input.krakenffnall} -s 5000 -o {output.splitdir}
		"""

rule doMasking:
	"""
	Rule to mask repetitive regions in fasta file
	"""
	input:
		fastafile = "{workingdirectory}/split_fasta/kraken.tax.{num}.fa"
	output:
		maskedfile = "{workingdirectory}/split_fasta/kraken.tax.{num}.masked.fa"
	conda: "envs/kraken.yaml"
	threads: 1
	shell:
		"""
		dustmasker -in {input.fastafile} -outfmt fasta | sed -e '/^>/!s/[a-z]/x/g' > {output.maskedfile}
		"""

def aggregate_masking(wildcards):
	checkpoint_output=checkpoints.SplitFasta.get(**wildcards).output[0]
	return expand ("{workingdirectory}/split_fasta/kraken.tax.{num}.masked.fa", workingdirectory=config["workingdirectory"], num=glob_wildcards(os.path.join(checkpoint_output, 'kraken.tax.{num}.fa')).num)

rule concatenate_masking:
	input:
		aggregate_masking
	output:
		"{workingdirectory}/kraken.tax.masked.ffn"
	shell:
		"""
		if [ -n "{input}" ]
		then
			cat {input} > {output}
		else
			touch {output}
		fi
		"""

rule CreateKrakenDB:
	"""
	Create Kraken DB for all downloaded refseq genomes
	"""
	input:
		donefile = "{workingdirectory}/taxdownload.done.txt",
		krakenffnall = "{workingdirectory}/kraken.tax.masked.ffn",
		krakenffnrel = "{workingdirectory}/relatives/relatives.kraken.tax.ffn",
		splitdir = directory("{workingdirectory}/split_fasta/"),
		krakenfasta = "{workingdirectory}/kraken.tax.ffn",
	output:
		krakendb = directory("{workingdirectory}/krakendb")
	threads: 10
	conda: "envs/kraken.yaml"
	shell:
		"""
		if [ -s {input.krakenffnall} ]
		then
			mkdir {output.krakendb}
			mkdir {output.krakendb}/taxonomy
			cp {datadir}/taxonomy/names.dmp {datadir}/taxonomy/nodes.dmp {datadir}/taxonomy/nucl_gb.accession2taxid {datadir}/taxonomy/nucl_wgs.accession2taxid  {output.krakendb}/taxonomy
			kraken2-build --threads {threads} --add-to-library {input.krakenffnall} --db {output.krakendb} --no-masking
			kraken2-build --threads {threads} --add-to-library {input.krakenffnrel} --db {output.krakendb} --no-masking
			kraken2-build --threads {threads} --build --kmer-len 50 --db {output.krakendb}
		else
			mkdir {output.krakendb}
		fi
		rm -r {input.splitdir}
		rm {input.krakenfasta}
		"""

rule RunKraken:
	"""
	Run Kraken on Hifi reads
	"""
	input:
		krakenffnall = "{workingdirectory}/kraken.tax.masked.ffn",
		krakendb = "{workingdirectory}/krakendb"
	output:
		krakenout = "{workingdirectory}/kraken.output",
		krakenreport = "{workingdirectory}/kraken.report"
	threads: 10
	conda: "envs/kraken.yaml"
	shell:
		"""
		if [ -s {input.krakenffnall} ]
		then
			if [[ {reads} == *gz ]] 
			then
				kraken2 --gzip-compressed --threads {threads} --report {output.krakenreport} --db {input.krakendb} {reads} > {output.krakenout}
			else
				kraken2 --threads {threads} --report {output.krakenreport} --db {input.krakendb} {reads} > {output.krakenout}
			fi
			rm -r {input.krakendb}/taxonomy/*
			rm -r {input.krakendb}/library/added/*
		else
			touch {output.krakenout}
			touch {output.krakenreport}
		fi
		"""

rule ExtractReadsKraken:
	"""
	For each genus extract the classified reads and get into fasta format
	"""
	input:
		krakenout = "{workingdirectory}/kraken.output",
		krakenreport = "{workingdirectory}/kraken.report",
		generafiles = "{workingdirectory}/genera/genus.{genus}.txt"
	output:
		krakenreads = "{workingdirectory}/{genus}/kraken.reads",
		krakenfa = "{workingdirectory}/{genus}/kraken.fa"
	conda: "envs/seqtk.yaml"
	shell:
		"""
		python {scriptdir}/KrakenReadsPerGenus.py -i {input.krakenout} -rep {input.krakenreport} -g {input.generafiles} -r {output.krakenreads}
		seqtk subseq {reads} {output.krakenreads} > {output.krakenfa}
		"""

rule Map2Assembly:
	input:
		krakenffnall = "{workingdirectory}/kraken.tax.masked.ffn",
		krakenfa = "{workingdirectory}/{genus}/kraken.fa"
	output:
		paffile = "{workingdirectory}/{genus}/{genus}.paf",
		mapping = "{workingdirectory}/{genus}/{genus}.ctgs",
		contiglist = "{workingdirectory}/{genus}/{genus}.ctgs.list",
		reads = "{workingdirectory}/{genus}/{genus}.reads",
		fasta = "{workingdirectory}/{genus}/{genus}.ctgs.fa"
	threads: 10
	conda: "envs/minimap.yaml"
	shell:
		"""
		if [ -s {input.krakenffnall} ]
		then
			minimap2 -x map-pb -t {threads} {genome} {input.krakenfa}  > {output.paffile}
			python {scriptdir}/PafAlignment.py -p {output.paffile} -o {output.mapping} -r {output.reads}
			grep -v 'NOT COMPLETE' {output.mapping} | cut -f1 | sort | uniq > {output.contiglist} || true
			seqtk subseq {genome} {output.contiglist} > {output.fasta}
		else
			touch {output.paffile} {output.mapping} {output.contiglist} {output.reads} {output.fasta}
		fi
		"""

rule RunBusco:
	"""
	Detect number of BUSCO genes per contig
	"""
	input:
		circgenome = "{workingdirectory}/{genus}/{genus}.ctgs.fa",
		taxnames = expand("{datadir}/taxonomy/names.dmp",datadir=config["datadir"]),
		taxnodes = expand("{datadir}/taxonomy/nodes.dmp",datadir=config["datadir"]),
	params:
		buscodir = directory("{workingdirectory}/{genus}/busco")
	output:
		buscodbs = "{workingdirectory}/{genus}/info_dbs.txt",
		buscoini = "{workingdirectory}/{genus}/config_busco.ini",
		#proteins = "{workingdirectory}/{genus}/busco/busco/prodigal_output/predicted_genes/predicted.faa",
		completed = "{workingdirectory}/{genus}/busco/done.txt"
	conda: "envs/busco.yaml"
	threads:
		10
	shell:
		"""
		if [ -s {input.circgenome} ]; then
			busco --list-datasets > {output.buscodbs}
			python {scriptdir}/BuscoConfig.py -na {input.taxnames} -no {input.taxnodes} -f {input.circgenome} -d {params.buscodir} -dl {datadir}/busco_data/ -c {threads} -db {output.buscodbs} -o {output.buscoini}
			busco --config {output.buscoini} -f || true
		else
			touch {output.buscodbs}
			touch {output.buscoini}
		fi
		touch {output.completed}
		"""

rule NucmerRefSeqContigs:
	"""
	Alignment all contigs against reference genomes
	"""
	input:
		circgenome = "{workingdirectory}/{genus}/{genus}.ctgs.fa",
		buscotable = "{workingdirectory}/{genus}/busco/done.txt",
		refseqmasked = "{workingdirectory}/genera/{genus}.kraken.tax.ffn"
	output:
		completed = "{workingdirectory}/{genus}/nucmer_contigs.done.txt",
		nucmerdelta = "{workingdirectory}/{genus}/{genus}_vs_contigs.delta",
        nucmercoords = "{workingdirectory}/{genus}/{genus}_vs_contigs.coords.txt",
		nucmercontigs = "{workingdirectory}/{genus}/{genus}_vs_contigs.overview.txt"
	conda: "envs/nucmer.yaml"
	shell:
		"""
		if [ -s {input.circgenome} ]; then
			nucmer --maxmatch --delta {output.nucmerdelta} {input.circgenome} {input.refseqmasked}
			show-coords -c -l -L 100 -r -T {output.nucmerdelta} > {output.nucmercoords}
			python {scriptdir}/ParseNucmer.py -n {output.nucmercoords} -o {output.nucmercontigs}
		else
			touch {output.nucmerdelta}
			touch {output.nucmercoords}
			touch {output.nucmercontigs}
		fi
		touch {output.completed}
		"""

rule ClusterBusco:
	"""
	Detect number of genomes in assembly based on busco genes and coverage
	"""
	input:
		assemblyinfo = "{workingdirectory}/{genus}/{genus}.ctgs",
		completed = "{workingdirectory}/{genus}/busco/done.txt",
		nucmercontigs = "{workingdirectory}/{genus}/{genus}_vs_contigs.overview.txt",
		circgenome = "{workingdirectory}/{genus}/{genus}.ctgs.fa",
		krakenfa = "{workingdirectory}/{genus}/kraken.fa",
		krakenreads = "{workingdirectory}/{genus}/kraken.reads",
		reads = "{workingdirectory}/{genus}/{genus}.reads"
	output:
		summary = "{workingdirectory}/{genus}/busco/completeness_per_contig.txt",
		finalassembly = "{workingdirectory}/{genus}/{genus}.finalassembly.fa",
		contigsid = "{workingdirectory}/{genus}/{genus}.ids.txt",
		readids = "{workingdirectory}/{genus}/{genus}.readsids.txt",
		finalreads = "{workingdirectory}/{genus}/{genus}.final_reads.fa",
		nucmercontiglist = "{workingdirectory}/{genus}/{genus}.nucmer.contigs.txt",
		buscocontiglist = "{workingdirectory}/{genus}/{genus}.busco.contigs.txt",
		unmapped = "{workingdirectory}/{genus}/{genus}.unmapped.reads",
		unmappedfa = "{workingdirectory}/{genus}/{genus}.unmapped.fa",
	conda: "envs/seqtk.yaml"
	shell:
		"""
		if [ -s {input.circgenome} ]; then
			python {scriptdir}/ParseBuscoTableMapping.py -d {input.completed} -i {input.assemblyinfo} -o {output.summary} 
			grep -v 'NOT COMPLETE' {input.nucmercontigs} | cut -f1 | sort | uniq > {output.nucmercontiglist} || true
			cut -f1 {output.summary} | sort | uniq | grep -v '^#' > {output.buscocontiglist} || true
			cat  {output.buscocontiglist} {output.nucmercontiglist} | sort | uniq > {output.contigsid} || true
			if [ -s {output.contigsid}  ]; then
				seqtk subseq {input.circgenome} {output.contigsid} > {output.finalassembly}
				python {scriptdir}/SelectReads.py -r {input.reads} -o {output.readids} -c {output.contigsid}
				seqtk subseq {input.krakenfa} {output.readids} > {output.finalreads}
				comm -23 <(sort {input.krakenreads}) <(sort {output.readids}) > {output.unmapped}
				seqtk subseq {input.krakenfa} {output.unmapped} > {output.unmappedfa}
			else
				touch {output.finalassembly}
				touch {output.readids}
				touch {output.finalreads}
				touch {output.unmapped}
				cp {input.krakenfa} {output.unmappedfa}
			fi
		else
			touch {output.summary}
			touch {output.finalassembly}
			touch {output.contigsid}
			touch {output.readids}
			touch {output.finalreads}
			touch {output.nucmercontiglist}
			touch {output.buscocontiglist}
			touch {output.unmapped}
			touch {output.unmappedfa}
		fi
		"""

rule AddMappingReads:
	"""
	Add all reads mapping to contigs detected in Map2Assembly
	"""
	input:
		readsmap = "{workingdirectory}/AllReadsGenome.reads",
		mapping = "{workingdirectory}/{genus}/{genus}.ctgs",
		krakenfa = "{workingdirectory}/{genus}/kraken.reads"
	output:
		readslist = "{workingdirectory}/{genus}/{genus}.allreads",
		finalreads = "{workingdirectory}/{genus}/{genus}.finalreads",
		finalreadfasta = "{workingdirectory}/{genus}/{genus}.finalreads.fa"
	conda: "envs/seqtk.yaml"
	shell:
		"""
		python {scriptdir}/MappedContigs.py -m {input.mapping} -r {input.readsmap} > {output.readslist}
		cat {output.readslist} {input.krakenfa} | sort | uniq > {output.finalreads}
		seqtk subseq {reads} {output.finalreads} > {output.finalreadfasta}
 		"""

rule Hifiasm:
	"""
	Run hifiasm assembly on kraken classfied reads
	"""
	input:
		finalreadfasta = "{workingdirectory}/{genus}/{genus}.finalreads.fa"
	params:
		assemblyprefix = "{workingdirectory}/{genus}/hifiasm/hifiasm"
	output:
		completed = "{workingdirectory}/{genus}/assembly.done.txt",
		dirname = directory("{workingdirectory}/{genus}/hifiasm"),
		gfa = "{workingdirectory}/{genus}/hifiasm/hifiasm.p_ctg.gfa",
		fasta = "{workingdirectory}/{genus}/hifiasm/hifiasm.p_ctg.fasta"
	threads: 10
	conda: "envs/hifiasm.yaml"
	shell:
		"""
		if [ ! -d {output.dirname} ]; then
  			mkdir {output.dirname}
		fi
		if [ -s {input.finalreadfasta} ]; then
			hifiasm -o {params.assemblyprefix} -t {threads} {input.finalreadfasta} -D 10 -l 1 -s 0.999 || true
			if [ -s {output.gfa} ]; then
				awk '/^S/{{print ">"$2"\\n"$3}}' {output.gfa} | fold > {output.fasta} || true
				faidx {output.fasta}
			else
				touch {output.fasta}
			fi 
		else
			touch {output.gfa} 
			touch {output.fasta} 
		fi
		touch {output.completed}
		"""

rule RunBuscoAssembly:
	"""
	Detect number of BUSCO genes per contig
	"""
	input:
		circgenome = "{workingdirectory}/{genus}/hifiasm/hifiasm.p_ctg.fasta",
		taxnames = expand("{datadir}/taxonomy/names.dmp",datadir=config["datadir"]),
		taxnodes = expand("{datadir}/taxonomy/nodes.dmp",datadir=config["datadir"]),
	params:
		buscodir = directory("{workingdirectory}/{genus}/buscoAssembly")
	output:
		buscodbs = "{workingdirectory}/{genus}/info_dbs_assembly.txt",
		buscoini = "{workingdirectory}/{genus}/config_busco_assembly.ini",
		completed = "{workingdirectory}/{genus}/buscoAssembly/done.txt",
	conda: "envs/busco.yaml"
	threads:
		10
	shell:
		"""
		if [ -s {input.circgenome} ]; then
			busco --list-datasets > {output.buscodbs}
			python {scriptdir}/BuscoConfig.py -na {input.taxnames} -no {input.taxnodes} -f {input.circgenome} -d {params.buscodir} -dl {datadir}/busco_data/ -c {threads} -db {output.buscodbs} -o {output.buscoini}
			busco --config {output.buscoini} -f || true
		else
			touch {output.buscodbs}
			touch {output.buscoini}
		fi
		touch {output.completed}
		"""

rule NucmerRefSeqHifiasm:
	"""
	Alignment all contigs against reference genomes
	"""
	input:
		circgenome = "{workingdirectory}/{genus}/hifiasm/hifiasm.p_ctg.fasta",
		buscotable = "{workingdirectory}/{genus}/buscoAssembly/done.txt",
		refseqmasked = "{workingdirectory}/genera/{genus}.kraken.tax.ffn"
	output:
		completed = "{workingdirectory}/{genus}/nucmer_hifiasm.done.txt",
		nucmerdelta = "{workingdirectory}/{genus}/{genus}_vs_hifiasm.delta",
        nucmercoords = "{workingdirectory}/{genus}/{genus}_vs_hifiasm.coords.txt",
		nucmercontigs = "{workingdirectory}/{genus}/{genus}_vs_hifiasm.overview.txt"
	conda: "envs/nucmer.yaml"
	shell:
		"""
		if [ -s {input.circgenome} ]; then
			nucmer --maxmatch --delta {output.nucmerdelta} {input.circgenome} {input.refseqmasked}
			show-coords -c -l -L 100 -r -T {output.nucmerdelta} > {output.nucmercoords}
			python {scriptdir}/ParseNucmer.py -n {output.nucmercoords} -o {output.nucmercontigs}
		else
			touch {output.nucmerdelta}
			touch {output.nucmercoords}
			touch {output.nucmercontigs}
		fi
		touch {output.completed}
		"""

rule Map2AssemblyHifiasm:
	input:
		krakenfa = "{workingdirectory}/{genus}/{genus}.finalreads.fa",
		assemblyfasta = "{workingdirectory}/{genus}/hifiasm/hifiasm.p_ctg.fasta",
		completed = "{workingdirectory}/{genus}/buscoAssembly/done.txt",
		unmapped = "{workingdirectory}/{genus}/{genus}.unmapped.reads",
		nucmercontigs = "{workingdirectory}/{genus}/{genus}_vs_hifiasm.overview.txt",
		readfile = "{workingdirectory}/{genus}/buscoReads.txt"
	output:
		summary = "{workingdirectory}/{genus}/buscoAssembly/completeness_per_contig.txt",
		buscocontiglist = "{workingdirectory}/{genus}/{genus}.buscoAssembly.contigs.txt",
		nucmercontiglist = "{workingdirectory}/{genus}/{genus}.NucmerAssembly.contigs.txt",
		contiglist = "{workingdirectory}/{genus}/{genus}.Assembly.contigs.txt",
		paffile = "{workingdirectory}/{genus}/{genus}.assembly.paf",
		fasta = "{workingdirectory}/{genus}/{genus}.assembly.fa",
		mapping = "{workingdirectory}/{genus}/{genus}.assembly.ctgs",
		reads = "{workingdirectory}/{genus}/{genus}.assembly.reads",
		reads_unmapped = "{workingdirectory}/{genus}/{genus}.assembly.unmapped.reads",
		readsfasta = "{workingdirectory}/{genus}/{genus}.putative_reads.fa",
		busco_assembly = "{workingdirectory}/{genus}/buscoReadsAssembly.txt",
		busco_assembly_hifi = "{workingdirectory}/{genus}/buscoReadsAssemblyHifi.txt"
	threads: 10
	conda: "envs/minimap.yaml"
	shell:
		"""
		if [ -s {input.assemblyfasta} ]; then
			python {scriptdir}/ParseBuscoTableMapping.py -d {input.completed} -i {input.assemblyfasta} -o {output.summary} 
			grep -v 'NOT COMPLETE' {input.nucmercontigs} | cut -f1 | sort | uniq > {output.nucmercontiglist} || true
		else
			touch {output.nucmercontiglist} 
			touch {output.summary}
		fi
		cut -f1 {output.summary} | sort | uniq | grep -v '^#' > {output.buscocontiglist} || true
		cat {output.buscocontiglist} {output.nucmercontiglist} | sort | uniq > {output.contiglist}
		seqtk subseq {input.assemblyfasta} {output.contiglist} > {output.fasta}
		minimap2 -x map-pb -t {threads} {output.fasta} {input.krakenfa}  > {output.paffile}
		python {scriptdir}/PafAlignment.py -p {output.paffile} -o {output.mapping} -r {output.reads}
		comm -12 <(sort {input.unmapped}) <(cut -f2 {output.reads} | tr ',' '\n' | sort | uniq) > {output.reads_unmapped}
		comm -12 <(sort {input.unmapped}) <(sort {input.readfile}) > {output.busco_assembly}
		cat {output.reads_unmapped} {output.busco_assembly} | sort | uniq > {output.busco_assembly_hifi}
		seqtk subseq {input.krakenfa} {output.busco_assembly_hifi} > {output.readsfasta}
		"""

rule RunBuscoReads:
	"""
	Detect number of BUSCO genes per contig
	"""
	input:
		circgenome = "{workingdirectory}/{genus}/{genus}.finalreads.fa",
		taxnames = expand("{datadir}/taxonomy/names.dmp",datadir=config["datadir"]),
		taxnodes = expand("{datadir}/taxonomy/nodes.dmp",datadir=config["datadir"]),
	params:
		buscodir = directory("{workingdirectory}/{genus}/buscoReads"),
		genus = "{genus}",
		workingdirectory = "{workingdirectory}"
	output:
		renamedfa = "{workingdirectory}/{genus}/kraken.renamed.fa",
		convtable = "{workingdirectory}/{genus}/kraken.convtable.txt",
		buscodbs = "{workingdirectory}/{genus}/info_dbs_reads.txt",
		buscoini = "{workingdirectory}/{genus}/config_busco_reads.ini",
		completed = "{workingdirectory}/{genus}/buscoReads/done.txt",
		readfile = "{workingdirectory}/{genus}/buscoReads.txt"
	conda: "envs/busco.yaml"
	threads:
		10
	shell:
		"""
		if [ -s {input.circgenome} ]; then
			linecount=$(wc -l < {input.circgenome})
			if [ $linecount -le 100000 ]; then
				python {scriptdir}/RenameFastaHeader.py -i {input.circgenome} -o {output.convtable} > {output.renamedfa}
				busco --list-datasets > {output.buscodbs}
				python {scriptdir}/BuscoConfig.py -na {input.taxnames} -no {input.taxnodes} -f {output.renamedfa} -d {params.buscodir} -dl {datadir}/busco_data/ -c {threads} -db {output.buscodbs} -o {output.buscoini}
				busco --config {output.buscoini} -f || true
				touch {output.completed}
				python {scriptdir}/ParseBuscoTableMappingRead.py -d {output.completed} -c {output.convtable} -o {output.readfile}
			else
				touch {output.renamedfa} {output.convtable} {output.buscodbs} {output.buscoini} {output.readfile}
			fi
		else 
			touch {output.renamedfa}
			touch {output.convtable}
			touch {output.buscodbs}
			touch {output.buscoini}
			touch {output.readfile}
		fi
		touch {output.completed}
		"""

rule DrawCircos:
	"""
	Draw circos plot of re-assembly
	"""
	input:
		assemblyfasta = "{workingdirectory}/{genus}/hifiasm/hifiasm.p_ctg.fasta",
		contiglist = "{workingdirectory}/{genus}/{genus}.Assembly.contigs.txt",
		completed = "{workingdirectory}/{genus}/buscoAssembly/done.txt"
	params:
		dirname = "{workingdirectory}/{genus}/"
	output:
		karyo = "{workingdirectory}/{genus}/circos.karyo",
		cdsfile = "{workingdirectory}/{genus}/busco.cds.dat",
		linkfile = "{workingdirectory}/{genus}/links.dat",
		conffile = "{workingdirectory}/{genus}/circos.conf",
		figure = "{workingdirectory}/{genus}/circos.png"
	conda: "envs/circos.yaml"
	shell:
		"""
		linecount=$(wc -l < {input.contiglist})
		if [ $linecount -le 200 ]; then
			python {scriptdir}/input_circos.py -f {input.assemblyfasta} -c {input.contiglist} -b {input.completed} -k {output.karyo} -d {output.cdsfile} -l {output.linkfile}
			python {scriptdir}/config_circos.py -k {output.karyo} -d {output.cdsfile} -l {output.linkfile} > {output.conffile}
			circos -conf {output.conffile} -outputdir {params.dirname}
		else
			touch {output.karyo}
			touch {output.cdsfile}
			touch {output.linkfile}
			touch {output.conffile}
			touch {output.figure}
		fi
		"""
		
def aggregate_assemblies(wildcards):
	checkpoint_output=checkpoints.GetGenera.get(**wildcards).output[0]
	return expand ("{workingdirectory}/{genus}/{genus}.finalassembly.fa", workingdirectory=config["workingdirectory"], genus=glob_wildcards(os.path.join(checkpoint_output, 'genus.{genus}.txt')).genus)

rule concatenate_asm:
	input:
		aggregate_assemblies
	output:
		"{workingdirectory}/final_assembly.fa"
	shell:
		"""
		if [ -n "{input}" ]
		then
			cat {input} > {output}
		else
			touch {output}
		fi
		"""

def aggregate_readsets(wildcards):
	checkpoint_output=checkpoints.GetGenera.get(**wildcards).output[0]
	return expand ("{workingdirectory}/{genus}/{genus}.final_reads.fa", workingdirectory=config["workingdirectory"], genus=glob_wildcards(os.path.join(checkpoint_output, 'genus.{genus}.txt')).genus)

rule concatenate_reads:
	input:
		aggregate_readsets
	output:
		"{workingdirectory}/final_reads_removal.fa"
	shell:
		"""
		if [ -n "{input}" ]
		then
			cat {input} > {output}
		else
			touch {output}
		fi
		"""

def aggregate_readsetslist(wildcards):
	checkpoint_output=checkpoints.GetGenera.get(**wildcards).output[0]
	return expand ("{workingdirectory}/{genus}/{genus}.readsids.txt", workingdirectory=config["workingdirectory"], genus=glob_wildcards(os.path.join(checkpoint_output, 'genus.{genus}.txt')).genus)

rule concatenate_readlist:
	input:
		aggregate_readsetslist
	output:
		cont = "{workingdirectory}/final_reads_removal.txt",
		target = "{workingdirectory}/final_reads_target.fa.gz"
	shell:
		"""
		if [ -n "{input}" ]
		then
			cat {input} > {output.cont}
			if [[ {reads} == *gz ]] 
			then
				zcat {reads} | paste - - - - | grep -v -F -f {output.cont} | tr "\t" "\n" | gzip > {output.target}
			else
				cat {reads} | grep -v -F -f {output.cont} | gzip > {output.target}
			fi
		else
			touch {output.cont}
			cp {reads} {output.target}
		fi
		"""

def aggregate_readsets_putative(wildcards):
	checkpoint_output=checkpoints.GetGenera.get(**wildcards).output[0]
	return expand ("{workingdirectory}/{genus}/{genus}.putative_reads.fa", workingdirectory=config["workingdirectory"], genus=glob_wildcards(os.path.join(checkpoint_output, 'genus.{genus}.txt')).genus)

rule concatenate_reads_putative:
	input:
		aggregate_readsets_putative
	output:
		"{workingdirectory}/putative_reads_removal.fa"
	shell:
		"""
		if [ -n "{input}" ]
		then
			cat {input} > {output}
		else
			touch {output}
		fi
		"""

def aggregate_figures(wildcards):
	checkpoint_output=checkpoints.GetGenera.get(**wildcards).output[0]
	return expand ("{workingdirectory}/{genus}/circos.png", workingdirectory=config["workingdirectory"], genus=glob_wildcards(os.path.join(checkpoint_output, 'genus.{genus}.txt')).genus)

rule concatenate_figures:
	input:
		aggregate_figures
	output:
		"{workingdirectory}/figures_done.txt"
	shell:
		"touch {output}"

rule create_report:
	input:
		finalrem = "{workingdirectory}/final_reads_removal.fa",
		krakenout = "{workingdirectory}/kraken.output",
		putrem = "{workingdirectory}/putative_reads_removal.fa",
		figs = "{workingdirectory}/figures_done.txt"
	params:
		datadir = expand("{datadir}/genera/",datadir=config["datadir"])
	output:
		rep = "{workingdirectory}/{shortname}.report.pdf"
	conda: "envs/fpdf.yaml"
	shell:
		"""
		python {scriptdir}/ReportFile.py -o {output.rep} -r {input.finalrem} -d {params.datadir}
		gzip {input.krakenout}
		"""
