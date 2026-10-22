#!/usr/bin/env bash
# Shared, read-only SSB resources under the laboratory index root.

export SSB_INDEX_ROOT="/inputs/reference"
export SSB_REFERENCE_BUNDLE="${SSB_INDEX_ROOT}/SSB/GRCh38.p14.R48_20250509"
export SSB_REFERENCE_FASTA="${SSB_REFERENCE_BUNDLE}/GRCh38.p14.v48.genome.fa"
export SSB_REFERENCE_FAI="${SSB_REFERENCE_FASTA}.fai"
export SSB_BWA_PREFIX="${SSB_REFERENCE_BUNDLE}/Bwa_index/GRCh38.p14.v48"
export SSB_GTF="${SSB_REFERENCE_BUNDLE}/GRCh38.p14.v48.chr_patch_hapl_scaff.annotation.gtf"
export SSB_GFF3="${SSB_REFERENCE_BUNDLE}/GRCh38.p14.v48.gff3"
export SSB_GENE_BED="${SSB_REFERENCE_BUNDLE}/SSB_bed/GRCh38.p14.v48.per_g.bed"
export SSB_TRANSCRIPT_BED="${SSB_REFERENCE_BUNDLE}/SSB_bed/GRCh38.p14.v48.per_t.bed"
export SSB_TSS_BED="${SSB_REFERENCE_BUNDLE}/SSB_bed/GRCh38.p14.v48.per_t.tss_add200.bed"
export SSB_EXON_BED="${SSB_REFERENCE_BUNDLE}/SSB_bed/GRCh38.p14.v48.per_t.exon.bed"
export SSB_INTRON_BED="${SSB_REFERENCE_BUNDLE}/SSB_bed/GRCh38.p14.v48.per_t.intron.bed"
export SSB_REPEATMASKER_BED="${SSB_REFERENCE_BUNDLE}/hg38.ucsc.repeatmasker_0512.bed"
