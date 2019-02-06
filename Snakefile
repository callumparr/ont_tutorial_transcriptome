import os
import re
from os import path
import pandas as pd
from collections import OrderedDict
from snakemake.remote.HTTP import RemoteProvider as HTTPRemoteProvider

HTTP = HTTPRemoteProvider()


configfile: "config.yaml"

ProvidedTranscriptomeLink = config["transcriptome"]
ProvidedAnnotationLink  = config["annotation"]

downloadSource = {}
def checkExternalLinks(xlink):
  yfile = xlink
  p = re.compile("(^http:|^ftp:|^https:)")
  if (p.search(xlink)):
    yfile = os.path.basename(xlink)
    ylink = re.sub("^[^:]+://", "", xlink)
    downloadSource[yfile]=ylink
  return yfile

TranscriptomeFasta = checkExternalLinks(ProvidedTranscriptomeLink)
AnnotationGTF = checkExternalLinks(ProvidedAnnotationLink)

unzipDict = {}
def handleExternalZip(xfile):
  yfile = re.sub("\.gz$","",xfile)
  if (yfile != xfile):
    unzipDict[yfile]=xfile
  return yfile

UnpackedTranscriptomeFasta = handleExternalZip(TranscriptomeFasta)
UnpackedAnnotationGTF = handleExternalZip(AnnotationGTF)


# extract samples from the configfile
Samples = []
for i in range(len(config["Samples"])):
  dataSlice = config["Samples"][i]
  conditionSamples = list(list(dataSlice.items())[0][1].items())
  for j in range(len(conditionSamples)):
    sequenceFile = conditionSamples[j][1]
    sequenceFile = re.sub("RawData/","",sequenceFile) # this should be abstracted
    #print(sequenceFile)
    Samples.append(sequenceFile)

# Split the filenames into basename and extension
files = [filename.split('.', 1) for filename in Samples]
# Create a dictionary of mapping basename:extension
file_dict = {filename[0]: filename[1] if len(filename) == 2 else '' for filename in files}




rule all:
    input:
      expand("Analysis/samtools/{seqid}.flagstat", seqid=file_dict.keys()), 
      expand("Analysis/Salmon/{seqid}", seqid=file_dict.keys()), 
      "Analysis/ReferenceData/"+UnpackedAnnotationGTF
      
      
rule DownloadRemoteFile:
  input: lambda wildcards: HTTP.remote(downloadSource[wildcards.downloadFile])
  output:
    ancient("ReferenceData/{downloadFile}")
  shell:
    'mv {input} {output}'


rule UnpackPackedFile:
  input: lambda wildcards: ("ReferenceData/"+unzipDict[wildcards.unzipFile])
  output:
    ancient("Analysis/ReferenceData/{unzipFile}")
  shell:
    #"gunzip --keep -d {input}" --keep is obvious by missing from e.g. Centos 7
    "gunzip -c {input} > {output}"


rule build_minimap_index: ## build minimap2 index
    input:
        genome = "Analysis/ReferenceData/"+UnpackedTranscriptomeFasta
    output:
        index = "Analysis/Minimap2/transcriptome_index.mmi"
    params:
        opts = config["minimap_index_opts"]
    threads: config["threads"]
    shell:"""
        minimap2 -t {threads} {params.opts} -I 1000G -d {output.index} {input.genome}
    """

rule map_reads: ## map reads using minimap2
    input:
       index = rules.build_minimap_index.output.index,
       fastq = lambda wc: "RawData/" + wc.seqid + "." + file_dict[wc.seqid]
    output:
       bam = "Analysis/Minimap2/{seqid}.bam",
       sbam = "Analysis/Minimap2/{seqid}.sorted.bam",
    params:
        opts = config["minimap2_opts"],
        msec = config["maximum_secondary"],
        psec = config["secondary_score_ratio"]
    threads: config["threads"]
    shell:"""
    minimap2 -t {threads} -ax map-ont -p {params.psec} -N {params.msec} {params.opts} {input.index} {input.fastq}\
    | samtools view -Sb > {output.bam};
    samtools sort -@ {threads} {output.bam} -o {output.sbam};
    samtools index {output.sbam};
    """

rule flagstat:
  input:
    "Analysis/Minimap2/{seqid}.bam"
  output:
    "Analysis/samtools/{seqid}.flagstat"
  shell:
    "samtools flagstat {input} > {output}"


rule count_reads:
    input:
        bam = "Analysis/Minimap2/{seqid}.sorted.bam",
        trs = ancient("Analysis/ReferenceData/"+UnpackedTranscriptomeFasta),
    output:
        tsv = "Analysis/Salmon/{seqid}",
    params:
        libtype = config["salmon_libtype"],
    threads: config["threads"]
    shell: """
        salmon quant --noErrorModel -p {threads} -t {input.trs} -l {params.libtype} -a {input.bam} -o {output.tsv}
    """
