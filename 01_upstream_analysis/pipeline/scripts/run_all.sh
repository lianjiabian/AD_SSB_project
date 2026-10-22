#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
if [[ -r "$PROJECT_DIR/resources.env.sh" ]]; then
  source "$PROJECT_DIR/resources.env.sh"
fi

usage() {
  cat <<'USAGE'
Run the full SSB workflow in one command.

This wrapper runs:
  1. FASTQ -> deduplicated SSB breakpoints
  2. GTF -> transcript-region bins
  3. Breakpoint counts over bins
  4. Plot-ready matrix -> SVG profile plot

Required:
  --fastq-dir DIR          Directory containing paired FASTQ files

Reference (the shared SSB bundle is used by default):
  --ref-dir DIR            GRCh38.p14.R48_20250509 reference directory
      or override individual files with:
  --reference-prefix PATH  BWA/BWA-MEM2 index prefix
  --reference-fasta PATH   Reference genome FASTA
  --gtf FILE               GTF annotation for gene-region bins

Optional:
  --outdir DIR             Main pipeline output directory [ssb_run]
  --profile-outdir DIR     Profile output directory [Profiling_File2]
  --sample-list FILE       One sample id per line; auto-detected if omitted
  --threads N              Threads per sample [8]
  --jobs N                 Samples processed concurrently in main pipeline [1]
  --profile-jobs N         Samples processed concurrently in profile step [1]
  --aligner auto|bwa|bwa-mem2
  --mapq N                 Minimum mapping quality [20]
  --flag-r1 SEQ            R1 SSB flag [GGGGGGGGGG]
  --flag-r2 SEQ            R2 SSB flag [TTTTTTTTTTTT]
  --polya-window N         Internal polyA window [40]
  --polya-cutoff FLOAT     Internal polyA T-ratio cutoff [0.4]
  --gene-bed FILE          Optional gene BED annotation
  --tss-bed FILE           Optional TSS BED annotation
  --exon-bed FILE          Optional exon BED annotation
  --intron-bed FILE        Optional intron BED annotation
  --prefix NAME            Region-bin prefix [GRCh38.Allgene]
  --plot-width N           SVG plot width [1400]
  --plot-height N          SVG plot height [700]
  --keep-temp              Keep temporary files from main pipeline
  --force                  Rerun steps even when checkpoints exist
  --skip-env-check         Do not run scripts/utils/check_env.sh
  --skip-plot              Do not generate SVG plot
  -h, --help               Show this help

Example:
  bash scripts/run_all.sh \
    --fastq-dir 1_Fastq_Data \
    --ref-dir /inputs/reference/GRCh38.p14.R48_20250509 \
    --threads 16 \
    --jobs 2 \
    --profile-jobs 4
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  printf '[%(%F %T)T] %s\n' -1 "$*" >&2
}

FASTQ_DIR=""
REF_DIR="${SSB_REFERENCE_BUNDLE:-/inputs/reference/GRCh38.p14.R48_20250509}"
REFERENCE_PREFIX=""
REFERENCE_FASTA=""
GTF=""
OUTDIR="ssb_run"
PROFILE_OUTDIR="Profiling_File2"
SAMPLE_LIST=""
THREADS=8
JOBS=1
PROFILE_JOBS=1
ALIGNER="auto"
MAPQ=20
FLAG_R1="GGGGGGGGGG"
FLAG_R2="TTTTTTTTTTTT"
POLYA_WINDOW=40
POLYA_CUTOFF=0.4
GENE_BED=""
TSS_BED=""
EXON_BED=""
INTRON_BED=""
PREFIX="GRCh38.Allgene"
PLOT_WIDTH=1400
PLOT_HEIGHT=700
KEEP_TEMP=0
FORCE=0
SKIP_ENV_CHECK=0
SKIP_PLOT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fastq-dir) FASTQ_DIR="$2"; shift 2 ;;
    --ref-dir) REF_DIR="$2"; shift 2 ;;
    --reference-prefix) REFERENCE_PREFIX="$2"; shift 2 ;;
    --reference-fasta) REFERENCE_FASTA="$2"; shift 2 ;;
    --gtf) GTF="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    --profile-outdir) PROFILE_OUTDIR="$2"; shift 2 ;;
    --sample-list) SAMPLE_LIST="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --profile-jobs) PROFILE_JOBS="$2"; shift 2 ;;
    --aligner) ALIGNER="$2"; shift 2 ;;
    --mapq) MAPQ="$2"; shift 2 ;;
    --flag-r1) FLAG_R1="$2"; shift 2 ;;
    --flag-r2) FLAG_R2="$2"; shift 2 ;;
    --polya-window) POLYA_WINDOW="$2"; shift 2 ;;
    --polya-cutoff) POLYA_CUTOFF="$2"; shift 2 ;;
    --gene-bed) GENE_BED="$2"; shift 2 ;;
    --tss-bed) TSS_BED="$2"; shift 2 ;;
    --exon-bed) EXON_BED="$2"; shift 2 ;;
    --intron-bed) INTRON_BED="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --plot-width) PLOT_WIDTH="$2"; shift 2 ;;
    --plot-height) PLOT_HEIGHT="$2"; shift 2 ;;
    --keep-temp) KEEP_TEMP=1; shift ;;
    --force) FORCE=1; shift ;;
    --skip-env-check) SKIP_ENV_CHECK=1; shift ;;
    --skip-plot) SKIP_PLOT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$FASTQ_DIR" ]] || die "--fastq-dir is required"

if [[ -n "$REF_DIR" ]]; then
  [[ -d "$REF_DIR" ]] || die "Reference directory not found: $REF_DIR"
  [[ -n "$REFERENCE_PREFIX" ]] || REFERENCE_PREFIX="$REF_DIR/Bwa_index/GRCh38.p14.v48"
  [[ -n "$REFERENCE_FASTA" ]] || REFERENCE_FASTA="$REF_DIR/GRCh38.p14.v48.genome.fa"
  [[ -n "$GTF" ]] || GTF="$REF_DIR/GRCh38.p14.v48.chr_patch_hapl_scaff.annotation.gtf"
  [[ -n "$GENE_BED" ]] || GENE_BED="$REF_DIR/SSB_bed/GRCh38.p14.v48.per_g.bed"
  [[ -n "$TSS_BED" ]] || TSS_BED="$REF_DIR/SSB_bed/GRCh38.p14.v48.per_t.tss_add200.bed"
  [[ -n "$EXON_BED" ]] || EXON_BED="$REF_DIR/SSB_bed/GRCh38.p14.v48.per_t.exon.bed"
  [[ -n "$INTRON_BED" ]] || INTRON_BED="$REF_DIR/SSB_bed/GRCh38.p14.v48.per_t.intron.bed"
  [[ "$PREFIX" != "GRCh38.Allgene" ]] || PREFIX="GRCh38.p14.v48"
fi

[[ -n "$REFERENCE_PREFIX" ]] || die "--reference-prefix is required"
[[ -n "$REFERENCE_FASTA" ]] || die "--reference-fasta is required"
[[ -n "$GTF" ]] || die "--gtf is required"
[[ -f "$REFERENCE_FASTA" ]] || die "Reference FASTA not found: $REFERENCE_FASTA"
[[ -f "$GTF" ]] || die "GTF not found: $GTF"
for ref_file in "$GENE_BED" "$TSS_BED" "$EXON_BED" "$INTRON_BED"; do
  [[ -z "$ref_file" || -f "$ref_file" ]] || die "Annotation BED not found: $ref_file"
done

pipeline_args=(
  --fastq-dir "$FASTQ_DIR"
  --reference-prefix "$REFERENCE_PREFIX"
  --reference-fasta "$REFERENCE_FASTA"
  --outdir "$OUTDIR"
  --threads "$THREADS"
  --jobs "$JOBS"
  --aligner "$ALIGNER"
  --mapq "$MAPQ"
  --flag-r1 "$FLAG_R1"
  --flag-r2 "$FLAG_R2"
  --polya-window "$POLYA_WINDOW"
  --polya-cutoff "$POLYA_CUTOFF"
)

[[ -z "$SAMPLE_LIST" ]] || pipeline_args+=(--sample-list "$SAMPLE_LIST")
[[ -z "$GENE_BED" ]] || pipeline_args+=(--gene-bed "$GENE_BED")
[[ -z "$TSS_BED" ]] || pipeline_args+=(--tss-bed "$TSS_BED")
[[ -z "$EXON_BED" ]] || pipeline_args+=(--exon-bed "$EXON_BED")
[[ -z "$INTRON_BED" ]] || pipeline_args+=(--intron-bed "$INTRON_BED")
[[ "$KEEP_TEMP" -eq 0 ]] || pipeline_args+=(--keep-temp)
[[ "$FORCE" -eq 0 ]] || pipeline_args+=(--force)

profile_pre_args=(
  --gtf "$GTF"
  --outdir "$PROFILE_OUTDIR/Tmp"
  --prefix "$PREFIX"
)
[[ "$FORCE" -eq 0 ]] || profile_pre_args+=(--force)

if [[ "$SKIP_ENV_CHECK" -eq 0 ]]; then
  log "Check runtime environment"
  bash "$SCRIPT_DIR/utils/check_env.sh"
fi

log "Run SSB breakpoint pipeline"
bash "$SCRIPT_DIR/pipeline/ssb_pipeline.sh" "${pipeline_args[@]}"

if [[ -z "$SAMPLE_LIST" ]]; then
  SAMPLE_LIST="$OUTDIR/SampleList.txt"
fi

REGION_BINS="$PROFILE_OUTDIR/Tmp/${PREFIX}.region_bins.bed"
MATRIX="$PROFILE_OUTDIR/region_bin_mean_matrix.tsv"
PLOT_SVG="$PROFILE_OUTDIR/region_bin_mean_profile.svg"

log "Build gene-region bins"
bash "$SCRIPT_DIR/profile/ssb_profiling_plot_pre.sh" "${profile_pre_args[@]}"

log "Count SSB breakpoints over gene-region bins"
profile_args=(
  --region-bins "$REGION_BINS"
  --sample-list "$SAMPLE_LIST"
  --break-bed-dir "$OUTDIR/5_Dedup_Bed"
  --outdir "$PROFILE_OUTDIR"
  --jobs "$PROFILE_JOBS"
)
[[ "$FORCE" -eq 0 ]] || profile_args+=(--force)
bash "$SCRIPT_DIR/profile/ssb_profile.sh" "${profile_args[@]}"

if [[ "$SKIP_PLOT" -eq 0 ]]; then
  log "Render gene-region profile SVG"
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="${PYTHON:-python3}"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="${PYTHON:-python}"
  else
    die "Missing python3/python"
  fi
  "$PYTHON_BIN" "$SCRIPT_DIR/utils/plot_region_profile.py" \
    --matrix "$MATRIX" \
    --output-svg "$PLOT_SVG" \
    --width "$PLOT_WIDTH" \
    --height "$PLOT_HEIGHT"
fi

log "Done"
log "Main output: $OUTDIR"
log "Profile matrix: $MATRIX"
if [[ "$SKIP_PLOT" -eq 0 ]]; then
  log "Profile SVG: $PLOT_SVG"
fi
