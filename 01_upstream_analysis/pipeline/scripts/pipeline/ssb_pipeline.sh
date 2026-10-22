#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd -- "$SCRIPT_DIR/../utils" && pwd)"

usage() {
  cat <<'USAGE'
SSB NGS pipeline

Required:
  --fastq-dir DIR          Directory containing paired FASTQ files
  --reference-prefix PATH  BWA index prefix
  --reference-fasta PATH   Reference genome FASTA for internal polyA filtering

Optional:
  --outdir DIR             Output directory [ssb_run]
  --sample-list FILE       One sample id per line; auto-detected if omitted
  --threads N              Threads per sample [8]
  --jobs N                 Number of samples processed concurrently [1]
  --aligner auto|bwa|bwa-mem2
                           Aligner command [auto]
  --mapq N                 Minimum mapping quality for break candidates [20]
  --flag-r1 SEQ            R1 SSB adapter/flag [GGGGGGGGGG]
  --flag-r2 SEQ            R2 SSB adapter/flag [TTTTTTTTTTTT]
  --polya-window N         Upstream/downstream bases checked for internal polyA [40]
  --polya-cutoff FLOAT     Remove break when T ratio is >= cutoff [0.4]
  --gene-bed FILE          Optional BED annotation for gene-level intersect
  --tss-bed FILE           Optional BED annotation for TSS intersect
  --exon-bed FILE          Optional BED annotation for exon intersect
  --intron-bed FILE        Optional BED annotation for intron intersect
  --keep-temp              Keep temporary BAM/BED files
  --force                  Rerun all steps even when checkpoint markers exist
  -h, --help               Show this help

FASTQ naming accepted by auto detection and pairing:
  SAMPLE_1.fq.gz / SAMPLE_2.fq.gz
  SAMPLE_1.fastq.gz / SAMPLE_2.fastq.gz
  SAMPLE_R1.fastq.gz / SAMPLE_R2.fastq.gz
  SAMPLE_R1_001.fastq.gz / SAMPLE_R2_001.fastq.gz

Example:
  bash scripts/ssb_pipeline.sh \
    --fastq-dir 1_Fastq_Data \
    --reference-prefix /inputs/reference/GRCh38.p14.R48_20250509/Bwa_index/GRCh38.p14.v48 \
    --reference-fasta /inputs/reference/GRCh38.p14.R48_20250509/GRCh38.p14.v48.genome.fa \
    --gene-bed /inputs/reference/GRCh38.p14.R48_20250509/SSB_bed/GRCh38.p14.v48.per_g.bed \
    --threads 16
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  printf '[%(%F %T)T] %s\n' -1 "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

FASTQ_DIR=""
OUTDIR="ssb_run"
SAMPLE_LIST=""
REFERENCE_PREFIX=""
REFERENCE_FASTA=""
GENE_BED=""
TSS_BED=""
EXON_BED=""
INTRON_BED=""
THREADS=8
JOBS=1
ALIGNER="auto"
MAPQ=20
FLAG_R1="GGGGGGGGGG"
FLAG_R2="TTTTTTTTTTTT"
POLYA_WINDOW=40
POLYA_CUTOFF=0.4
KEEP_TEMP=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fastq-dir) FASTQ_DIR="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    --sample-list) SAMPLE_LIST="$2"; shift 2 ;;
    --reference-prefix) REFERENCE_PREFIX="$2"; shift 2 ;;
    --reference-fasta) REFERENCE_FASTA="$2"; shift 2 ;;
    --gene-bed) GENE_BED="$2"; shift 2 ;;
    --tss-bed) TSS_BED="$2"; shift 2 ;;
    --exon-bed) EXON_BED="$2"; shift 2 ;;
    --intron-bed) INTRON_BED="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --aligner) ALIGNER="$2"; shift 2 ;;
    --mapq) MAPQ="$2"; shift 2 ;;
    --flag-r1) FLAG_R1="$2"; shift 2 ;;
    --flag-r2) FLAG_R2="$2"; shift 2 ;;
    --polya-window) POLYA_WINDOW="$2"; shift 2 ;;
    --polya-cutoff) POLYA_CUTOFF="$2"; shift 2 ;;
    --keep-temp) KEEP_TEMP=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$FASTQ_DIR" ]] || die "--fastq-dir is required"
[[ -d "$FASTQ_DIR" ]] || die "FASTQ directory not found: $FASTQ_DIR"
[[ -n "$REFERENCE_PREFIX" ]] || die "--reference-prefix is required"
[[ -n "$REFERENCE_FASTA" ]] || die "--reference-fasta is required"
[[ -f "$REFERENCE_FASTA" ]] || die "Reference FASTA not found: $REFERENCE_FASTA"
for ref_file in "$GENE_BED" "$TSS_BED" "$EXON_BED" "$INTRON_BED"; do
  [[ -z "$ref_file" || -f "$ref_file" ]] || die "Annotation BED not found: $ref_file"
done
[[ "$THREADS" =~ ^[0-9]+$ && "$THREADS" -ge 1 ]] || die "--threads must be a positive integer"
[[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || die "--jobs must be a positive integer"

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${PYTHON:-python3}"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${PYTHON:-python}"
else
  die "Missing python3/python"
fi

require_cmd samtools
require_cmd bedtools
require_cmd awk
require_cmd sort

check_bwa_index() {
  local prefix="$1"
  local missing=0
  local suffix
  for suffix in amb ann bwt pac sa; do
    if [[ ! -f "${prefix}.${suffix}" ]]; then
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]]
}

case "$ALIGNER" in
  auto)
    if command -v bwa >/dev/null 2>&1; then
      ALIGN_CMD=(bwa mem)
    elif command -v bwa-mem2 >/dev/null 2>&1; then
      ALIGN_CMD=(bwa-mem2 mem)
    else
      die "Missing aligner: install bwa or bwa-mem2"
    fi
    ;;
  bwa)
    require_cmd bwa
    ALIGN_CMD=(bwa mem)
    ;;
  bwa-mem2)
    require_cmd bwa-mem2
    ALIGN_CMD=(bwa-mem2 mem)
    ;;
  *)
    die "--aligner must be auto, bwa, or bwa-mem2"
    ;;
esac

if [[ "${ALIGN_CMD[0]}" == "bwa" ]] && ! check_bwa_index "$REFERENCE_PREFIX"; then
  die "BWA index files not found for prefix: $REFERENCE_PREFIX"
fi

FILTER_DIR="$OUTDIR/1_Filter"
BAM_DIR="$OUTDIR/2_Align_Bam"
CANDIDATE_DIR="$OUTDIR/3_Filter_Bed"
BREAK_DIR="$OUTDIR/4_Breaks_Bed"
DEDUP_DIR="$OUTDIR/5_Dedup_Bed"
GENE_ANNO_DIR="$OUTDIR/6_Anno_Bed"
TSS_ANNO_DIR="$OUTDIR/6_Tss_Anno_Bed"
EXON_ANNO_DIR="$OUTDIR/6_Exon_Anno_Bed"
INTRON_ANNO_DIR="$OUTDIR/6_Intron_Anno_Bed"
QC_DIR="$OUTDIR/qc"
LOG_DIR="$OUTDIR/logs"
TMP_DIR="$OUTDIR/tmp"
STATE_DIR="$OUTDIR/.workflow"

mkdir -p "$FILTER_DIR" "$BAM_DIR" "$CANDIDATE_DIR" "$BREAK_DIR" "$DEDUP_DIR" \
  "$QC_DIR" "$LOG_DIR" "$TMP_DIR" "$STATE_DIR"
[[ -n "$GENE_BED" ]] && mkdir -p "$GENE_ANNO_DIR"
[[ -n "$TSS_BED" ]] && mkdir -p "$TSS_ANNO_DIR"
[[ -n "$EXON_BED" ]] && mkdir -p "$EXON_ANNO_DIR"
[[ -n "$INTRON_BED" ]] && mkdir -p "$INTRON_ANNO_DIR"

generate_sample_list() {
  local outfile="$1"
  find "$FASTQ_DIR" -maxdepth 1 -type f \
    \( -name '*_1.fq.gz' -o -name '*_1.fastq.gz' -o -name '*_R1.fq.gz' \
       -o -name '*_R1.fastq.gz' -o -name '*_R1_001.fastq.gz' \
       -o -name '*_1.fq' -o -name '*_1.fastq' -o -name '*_R1.fq' \
       -o -name '*_R1.fastq' -o -name '*_R1_001.fastq' \) |
    sed -E 's#^.*/##; s/(_R1_001|_R1|_1)\.(fastq|fq)(\.gz)?$//' |
    sort -u > "$outfile"
}

if [[ -z "$SAMPLE_LIST" ]]; then
  SAMPLE_LIST="$OUTDIR/SampleList.txt"
  generate_sample_list "$SAMPLE_LIST"
else
  [[ -f "$SAMPLE_LIST" ]] || die "Sample list not found: $SAMPLE_LIST"
fi

[[ -s "$SAMPLE_LIST" ]] || die "No samples found"

find_read() {
  local sample="$1"
  local mate="$2"
  local suffixes=()
  if [[ "$mate" == "1" ]]; then
    suffixes=("_1.fq.gz" "_1.fastq.gz" "_R1.fq.gz" "_R1.fastq.gz" "_R1_001.fastq.gz" "_1.fq" "_1.fastq" "_R1.fq" "_R1.fastq" "_R1_001.fastq")
  else
    suffixes=("_2.fq.gz" "_2.fastq.gz" "_R2.fq.gz" "_R2.fastq.gz" "_R2_001.fastq.gz" "_2.fq" "_2.fastq" "_R2.fq" "_R2.fastq" "_R2_001.fastq")
  fi

  local suffix path
  for suffix in "${suffixes[@]}"; do
    path="$FASTQ_DIR/${sample}${suffix}"
    if [[ -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

step_marker() {
  local sample="$1"
  local step="$2"
  printf '%s/%s.%s.done\n' "$STATE_DIR" "$sample" "$step"
}

step_done() {
  local sample="$1"
  local step="$2"
  shift 2

  [[ "$FORCE" -eq 0 ]] || return 1
  [[ -s "$(step_marker "$sample" "$step")" ]] || return 1

  local output
  for output in "$@"; do
    [[ -e "$output" ]] || return 1
  done
}

mark_step_done() {
  local sample="$1"
  local step="$2"
  shift 2

  {
    printf 'sample=%s\n' "$sample"
    printf 'step=%s\n' "$step"
    printf 'completed_at=%(%F %T)T\n' -1
    printf 'outputs=%s\n' "$*"
  } > "$(step_marker "$sample" "$step")"
}

write_step_header() {
  local sample="$1"
  local step="$2"
  printf '[%(%F %T)T] start %s %s\n' -1 "$sample" "$step"
}

write_step_footer() {
  local sample="$1"
  local step="$2"
  printf '[%(%F %T)T] complete %s %s\n' -1 "$sample" "$step"
}

annotate_if_requested() {
  local sample="$1"
  local bed="$2"

  if [[ -n "$GENE_BED" ]]; then
    local out="$GENE_ANNO_DIR/${sample}.anno.bed"
    if step_done "$sample" "annotate_gene" "$out"; then
      log "[$sample] skip gene annotation"
    else
      {
        write_step_header "$sample" "annotate_gene"
        bedtools intersect -a "$GENE_BED" -b "$bed" -wa -wb > "$out"
        write_step_footer "$sample" "annotate_gene"
      } > "$LOG_DIR/${sample}.06_annotate_gene.log" 2>&1
      mark_step_done "$sample" "annotate_gene" "$out"
    fi
  fi
  if [[ -n "$TSS_BED" ]]; then
    local out="$TSS_ANNO_DIR/${sample}.anno.bed"
    if step_done "$sample" "annotate_tss" "$out"; then
      log "[$sample] skip TSS annotation"
    else
      {
        write_step_header "$sample" "annotate_tss"
        bedtools intersect -a "$TSS_BED" -b "$bed" -wa -wb > "$out"
        write_step_footer "$sample" "annotate_tss"
      } > "$LOG_DIR/${sample}.06_annotate_tss.log" 2>&1
      mark_step_done "$sample" "annotate_tss" "$out"
    fi
  fi
  if [[ -n "$EXON_BED" ]]; then
    local out="$EXON_ANNO_DIR/${sample}.anno.bed"
    if step_done "$sample" "annotate_exon" "$out"; then
      log "[$sample] skip exon annotation"
    else
      {
        write_step_header "$sample" "annotate_exon"
        bedtools intersect -a "$EXON_BED" -b "$bed" -wa -wb > "$out"
        write_step_footer "$sample" "annotate_exon"
      } > "$LOG_DIR/${sample}.06_annotate_exon.log" 2>&1
      mark_step_done "$sample" "annotate_exon" "$out"
    fi
  fi
  if [[ -n "$INTRON_BED" ]]; then
    local out="$INTRON_ANNO_DIR/${sample}.anno.bed"
    if step_done "$sample" "annotate_intron" "$out"; then
      log "[$sample] skip intron annotation"
    else
      {
        write_step_header "$sample" "annotate_intron"
        bedtools intersect -a "$INTRON_BED" -b "$bed" -wa -wb > "$out"
        write_step_footer "$sample" "annotate_intron"
      } > "$LOG_DIR/${sample}.06_annotate_intron.log" 2>&1
      mark_step_done "$sample" "annotate_intron" "$out"
    fi
  fi
}

run_sample() {
  local sample="$1"
  local r1 r2 trim_r1 trim_r2 bam tmp_bam candidates breaks dedup rg

  r1="$(find_read "$sample" 1)" || die "R1 FASTQ not found for sample: $sample"
  r2="$(find_read "$sample" 2)" || die "R2 FASTQ not found for sample: $sample"

  log "[$sample] filter SSB flags"
  trim_r1="$FILTER_DIR/${sample}_R1.trim.fastq.gz"
  trim_r2="$FILTER_DIR/${sample}_R2.trim.fastq.gz"
  if step_done "$sample" "filter_flags" "$trim_r1" "$trim_r2" "$QC_DIR/${sample}.filter_flags.json"; then
    log "[$sample] skip filter SSB flags"
  else
    {
      write_step_header "$sample" "filter_flags"
      "$PYTHON_BIN" "$UTILS_DIR/filter_paired_flags.py" \
        --r1 "$r1" \
        --r2 "$r2" \
        --out-r1 "$trim_r1" \
        --out-r2 "$trim_r2" \
        --flag-r1 "$FLAG_R1" \
        --flag-r2 "$FLAG_R2" \
        --stats "$QC_DIR/${sample}.filter_flags.json"
      write_step_footer "$sample" "filter_flags"
    } > "$LOG_DIR/${sample}.01_filter_flags.log" 2>&1
    mark_step_done "$sample" "filter_flags" "$trim_r1" "$trim_r2" "$QC_DIR/${sample}.filter_flags.json"
  fi

  log "[$sample] align and sort"
  bam="$BAM_DIR/${sample}.sorted.bam"
  rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
  if step_done "$sample" "align_sort" "$bam" "${bam}.bai" "$QC_DIR/${sample}.flagstat.txt"; then
    log "[$sample] skip align and sort"
  else
    {
      write_step_header "$sample" "align_sort"
      "${ALIGN_CMD[@]}" -t "$THREADS" -M -R "$rg" "$REFERENCE_PREFIX" "$trim_r1" "$trim_r2" |
        samtools view -@ "$THREADS" -b - |
        samtools sort -@ "$THREADS" -o "$bam" -
      samtools index -@ "$THREADS" "$bam"
      samtools flagstat -@ "$THREADS" "$bam" > "$QC_DIR/${sample}.flagstat.txt"
      write_step_footer "$sample" "align_sort"
    } > "$LOG_DIR/${sample}.02_align_sort.log" 2>&1
    mark_step_done "$sample" "align_sort" "$bam" "${bam}.bai" "$QC_DIR/${sample}.flagstat.txt"
  fi

  log "[$sample] build break candidates"
  tmp_bam="$TMP_DIR/${sample}.candidate_reads.bam"
  candidates="$CANDIDATE_DIR/${sample}.candidates.bed"
  if step_done "$sample" "candidate_bed" "$candidates"; then
    log "[$sample] skip break candidates"
  else
    {
      write_step_header "$sample" "candidate_bed"
      samtools view -h -q "$MAPQ" -F 4 "$bam" |
        awk 'BEGIN{OFS="\t"} /^@/ || $2 == 147 || $2 == 163 {print}' |
        samtools view -@ "$THREADS" -b -o "$tmp_bam" -

      bedtools bamtobed -tag NM -i "$tmp_bam" |
        awk 'BEGIN{OFS="\t"} $6=="+" {print $1,$2,$2+1,$4,$5,$6} $6=="-" {print $1,$3-1,$3,$4,$5,$6}' |
        sort -k1,1 -k2,2n > "$candidates"
      write_step_footer "$sample" "candidate_bed"
    } > "$LOG_DIR/${sample}.03_candidate_bed.log" 2>&1
    mark_step_done "$sample" "candidate_bed" "$candidates"
  fi

  log "[$sample] filter internal polyA"
  breaks="$BREAK_DIR/${sample}.breaks.bed"
  if step_done "$sample" "internal_polya" "$breaks" "$QC_DIR/${sample}.internal_polya.json"; then
    log "[$sample] skip internal polyA"
  else
    {
      write_step_header "$sample" "internal_polya"
      "$PYTHON_BIN" "$UTILS_DIR/filter_internal_polya.py" \
        --input-bed "$candidates" \
        --genome-fasta "$REFERENCE_FASTA" \
        --window "$POLYA_WINDOW" \
        --max-t-ratio "$POLYA_CUTOFF" \
        --output-bed "$breaks" \
        --stats "$QC_DIR/${sample}.internal_polya.json"
      write_step_footer "$sample" "internal_polya"
    } > "$LOG_DIR/${sample}.04_internal_polya.log" 2>&1
    mark_step_done "$sample" "internal_polya" "$breaks" "$QC_DIR/${sample}.internal_polya.json"
  fi

  log "[$sample] deduplicate breakpoints"
  dedup="$DEDUP_DIR/${sample}.deduplicated.bed"
  if step_done "$sample" "deduplicate" "$dedup"; then
    log "[$sample] skip deduplicate breakpoints"
  else
    {
      write_step_header "$sample" "deduplicate"
      sort -k1,1 -k2,2n -k3,3n -k6,6 "$breaks" |
        awk 'BEGIN{OFS="\t"} !seen[$1 FS $2 FS $3 FS $6]++' > "$dedup"
      write_step_footer "$sample" "deduplicate"
    } > "$LOG_DIR/${sample}.05_deduplicate.log" 2>&1
    mark_step_done "$sample" "deduplicate" "$dedup"
  fi

  annotate_if_requested "$sample" "$dedup"

  if [[ "$KEEP_TEMP" -eq 0 ]]; then
    rm -f "$tmp_bam"
  fi

  log "[$sample] done"
}

pids=()
while IFS= read -r sample || [[ -n "$sample" ]]; do
  [[ -n "$sample" ]] || continue
  [[ "$sample" =~ ^# ]] && continue

  if [[ "$JOBS" -eq 1 ]]; then
    run_sample "$sample"
  else
    run_sample "$sample" &
    pids+=("$!")
    while [[ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$JOBS" ]]; do
      sleep 2
    done
  fi
done < "$SAMPLE_LIST"

status=0
for pid in "${pids[@]}"; do
  wait "$pid" || status=1
done
exit "$status"
