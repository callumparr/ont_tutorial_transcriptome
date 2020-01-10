# Statement of tutorial objectives

The aim of this tutorial is to demonstrate a workflow for long-read differential isoform analysis based on cDNA sequence data. This workflow is suitable for fastq sequence collections with a paired design (e.g. tumour/normal) where a reference transcriptome sequence is available. 

The tutorial is packaged with example data, so that the workflow can be replicated to address questions such as

* which genes are expressed in my study?
* which genes are upregulated in this tumour sample?
* which gene isoforms show differential expression?
* show gene expression levels for gene *ENSG00000142937*
* show transcript expression levels for transcript *ENST00000464658*

Editing of the workflow's configuration file, **`config.yaml`**, will allow the workflow to be run with different starting cDNA sequence collections, different reference transcriptomes and with different statistical thresholds for the selection of genes displaying differential transcript usage.

## Methods utilised include: 

* **`conda`** for management of bioinformatics software installations
* **`snakemake`** for managing the bioinformatics workflow
* **`minimap2`** for mapping sequence reads to reference genome
* **`samtools`** for SAM/BAM handling and mapping statistics
* **`salmon`** for transcript quantification

## The computational requirements include: 

* Computer running Linux (Centos7, Ubuntu 18_10, Fedora 29)
* 8 Gb RAM is recommended 
* At least 5 Gb spare disk space for analysis and indices
* Runtime with provided example data - approximately 30 minutes

\pagebreak

# Software installation

1. Most of the software dependencies are managed though **`conda`**. Install as described at  <br> [https://conda.io/docs/install/quick.html](https://conda.io/docs/install/quick.html). You will need to accept the license agreement during installation and we recommended that you allow the conda installer to prepend its path to your `.bashrc` file when asked.
```
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    bash Miniconda3-latest-Linux-x86_64.sh
    bash
```
2. Download the tutorial & accompanying example files into a folder named `transcriptome_tutorial`. This tutorial requires the **`git-lfs`** large file support capabilities, which should be installed through **`conda`** first
```
    conda install -c conda-forge git-lfs
    git lfs install
    git clone https://github.com/nanoporetech/ont_tutorial_transcriptome.git transcriptome_tutorial
```
3. Change your working directory into the new `transcriptome_tutorial` folder 
```
    cd transcriptome_tutorial
```
4. Install software dependencies using conda
```
    conda env create --name transcriptome_tutorial --file environment.yaml
```
5. Initialise the conda environment 
```
    source activate transcriptome_tutorial
```



# Introduction

Differential gene expression (DGE) and differential transcript usage (DTU) analyses aim to identify genes and/or transcripts that show statistically (and magnitudinally) altered expression patterns in a studied biological system. The results of the differential analyses are presented in a quantitative format and therefore the degree of change (up or down regulation) between experimental conditions can be calculated for each gene identified.  

These differential analyses requires a "snapshot" of gene expression that can be used to quantify the abundance of the genes' transcripts and the relative abundance of their isoforms. In this context, abundance corresponds to the number of messenger RNAs (mRNA) measured from each gene isoform within the organism/tissue/culture being investigated. The greater the number of mRNA molecules observed from a given gene isoform, the higher its expression level. In order to determine expression levels across the whole genome, sequence data specifically targeting the mRNA molecules can be generated. 

[Oxford Nanopore Technologies](https://nanoporetech.com) provides a number of [sequencing solutions](https://nanoporetech.com/rna) to allow users to generate the required snapshot of gene expression. This can be achieved by both sequencing the mRNA [directly](https://store.nanoporetech.com/catalog/product/view/id/167/s/direct-rna-sequencing-kit/category/28/), or via a complementary DNA ([cDNA](https://store.nanoporetech.com/catalog/product/view/id/177/s/cdna-pcr/category/28/)) proxy. In contrast to short read sequencing technologies, entire mRNA transcripts can be captured as single reads. The example data provided with this tutorial is from a study based on the [PCR-cDNA](https://store.nanoporetech.com/catalog/product/view/id/177/s/cdna-pcr/category/28/) kit. This is a robust choice for performing differential transcript usage studies. This kit is suitable for preparation of sequence libraries from low mRNA input quantities. The cDNA population is [enriched through PCR with low bias](https://nanoporetech.com/resource-centre/low-bias-rna-seq-pcr-cdna-pcr-free-direct-cdna-and-direct-rna-sequencing); an important prerequisite for the subsequent statistical analysis.   

Once sequencing data has been produced from both the experimental and paired control samples (with an appropriate number of biological replicates), the sequence reads can be mapped to the organism's reference transcriptome. The number of sequences mapping to each gene isoform can be counted, and it is these count data that form the basis for the **`DGE`** and **`DTU`** analyses.  

There are five goals for this tutorial:

* To introduce a literate framework for analysing Oxford Nanopore cDNA data prepared using the MinION, GridION or PromethION
* To utilise best data-management practices
* To provide basic cDNA sequence QC metrics, enabling review and consideration of the starting experimental data
* To map sequence reads to the reference *transcriptome* and to identify the gene isoforms that are expressed and the number of sequence reads that are observed from each gene isoform (and parental gene).
* To perform a statistical analysis using **`edgeR`** (@R-edgeR2012) to identify differentially expressed genes and **`DEXSeq`** (@R-DEXSeq) and **`stageR`** (@R-stageR) to identify differentially used transcripts.


# Getting started and best practices

This tutorial requires a computer workstation running a Linux operating system. The workflow described has been tested using **`Fedora 29`**, **`Centos 7`** and **`Ubuntu 18_10`**. This tutorial has been prepared in the **`Rmarkdown`** file format. This utilises *markdown* (an easy-to-write plain text format as used in many Wiki systems) - see @R-rmarkdown for more information about **`rmarkdown`**. The document template contains chunks of embedded **`R code`** that are dynamically executed during the report preparation. 

The described analytical workflow makes extensive use of the **`conda`** package management and the **`snakemake`** workflow software. These software packages and the functionality of **`Rmarkdown`** provide the source for a rich, reproducible and extensible tutorial document.

The workflow contained within this tutorial performs a bioinformatics analysis using the annotated human transcriptome (*GRCh38 release 95*) as a reference sequence. 

There are several bioinformatics software dependencies that need to be installed prior to running the tutorial. The **`conda`** package management software will coordinate the installation of these software - this is dependent on a robust internet connection.

As a best practice this tutorial will separate primary cDNA sequence data (the base-called fastq files) from the **`Rmarkdown`** source and the transcriptome reference data. The analysis results and figures will again be placed in a separate working directory. The required layout for the primary data is shown in the figure below. This minimal structure will be prepared over the next sections of this tutorial. The cDNA sequences must be placed within a folder called **`RawData`** and the reference transcriptome and annotation files must be placed in a folder named **`ReferenceData`**.


![](Static/Images/FolderLayout.png) 

# Experimental setup

The first step for performing a cDNA sequence analysis involves collation of information on the biological samples and biological replicates that are to be used for the statistical analysis.

![](Static/Images/ExperimentalDesign.png) 

The example data included with this tutorial describes a study comparing an experimental sample against a linked control. The experimental and control samples have been prepared in triplicate. This design is described in a configuration file named **`config.yaml`** - an example file has been provided with the tutorial. The content of this file is highlighted in the figure above. The cDNA sequence files are defined within the **`Sample`** block; experimental groups and their discrete biological samples are defined here.

**`transcriptome`** refers to the reference *transcriptome* sequence against which the cDNA sequence reads will be mapped. **`annotation`** refers to the associated whole genome annotations for the corresponding genome sequence. This is required for linking transcripts to annotated transcripts and their parental genes. In this tutorial a URL is provided for both and the **`snakemake`** workflow will download the corresponding files. 

The configuration file provides additional parameters that can be used to provide further instructions to the **`minimap2`** software and provide thresholds for the minimal numbers of cDNA sequence reads that should be mapped to define a gene or its transcripts as expressed. 

The key parameters that should be considered include

* **`min_samps_gene_expr`** - the minimum number of experimental samples in which a gene should have mapped reads - this will remove genes and isoforms where only a sporadic pattern of expression is observed
* **`min_samps_feature_expr`** - the minimum number of samples in which a gene isoform should have mapped reads - this can be used to filter out isoforms with sporadic patterns of obsevation 
* **`min_gene_expr`** - the minimum number of sequence reads that must be observed to consider a gene for *DGE* analysis
* **`min_feature_expr`** - the minimum number of sequence reads that must be observed to consider a transcript for *DTU* analysis
* **`lfcThreshold`**  - the log2-fold-change filter to be applied in differential testing
* **`adjPValueThreshold`** - the false-discovery corrected p-value threshold to be used


## Example dataset

This tutorial is distributed with a collection of Oxford Nanopore cDNA sequence data in fastq format. The sequence collection provided corresponds to a renal cancer sample and its corresponding normal control. The sequence collection has been filtered and sub-sampled to provide a **synthetic dataset** that can be used to demonstrate this workflow. 

\newpage

# Snakemake

This tutorial for cDNA sequence analysis data uses **`snakemake`** (@snakemake2012). Snakemake is a workflow management system implemented in **`Python`**. The aim of the snakemake tool is to enable reproducible and scalable data analyses. The workflow produced within this document should be portable between laptop computers, computer servers and other larger scale IT deployments. The snakemake workflow requires a set of bioinformatics software. These software will be automatically downloaded and installed by the **conda** package management system.

The **`snakemake`** workflow will call methods that include **`minimap2`** (@minimap22018), **`samtools`** (@samtools2009) and **`salmon`** (@Salmon2017). The planned workflow is shown in the figure below. The remainder of the analysis will be performed in the **`R analysis`** described within the report.

![](Static/Images/dag1.png) 

The precise commands within the **`Snakefile`** based workflow include

* download the specified reference transcriptome
* download the specified genome annotations
* use **`minimap2`** to index the reference genome
* map cDNA sequence reads against the reference transcriptome index using **`minimap2`**
* convert **`minimap2`** output (**`SAM`**) into a sorted **`BAM`** format using **`samtools`**
* prepare summary mapping statistics using **`samtools flagstat`**
* count cDNA sequence reads for gene isoforms using **`salmon`**

# Run the snakemake workflow file

The snakemake command is responsible for orchestrating the analytical workflow. The command below shows how the **`snakemake`** command can be run

\fontsize{8}{12}
```
# just type snakemake to run the workflow
# don't type <NPROC> but specify the number of processor cores available (e.g. 2 or 4)

snakemake -j <NPROC>
```
\fontsize{10}{14}


\pagebreak
 

# Prepare the analysis report

The **`Rmarkdown`** script can be run usimg the **`knit`** dialog in the **`Rstudio`** software. The **`Rstudio`** software is installed during the **`conda`** environment build. Please see the figure below for a screenshot of the **`Rstudio`** interface showing the **`knit`** icon. Selecting **`Knit to HTML`** will prepare a portable HTML file. 

![](Static/Images/KnitIt.png) 

The document can also be rendered from the command line with the following command

\fontsize{8}{12}
```
R --slave -e 'rmarkdown::render("Nanopore_Transcriptome_Tutorial.Rmd", "html_document")'
```
\fontsize{10}{14}

