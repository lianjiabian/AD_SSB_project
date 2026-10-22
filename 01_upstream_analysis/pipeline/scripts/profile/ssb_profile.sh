#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd -- "$SCRIPT_DIR/../utils" && pwd)"

usage() {
  cat <<'USAGE'
SSB metagene/profile bin counting

This script counts deduplicated SSB breakpoints over transcript-region bins.
It can build bins from a GTF first, or reuse an existing region-bins BED.

Required for counting:
  --sample-list FILE       One sample id per line
  --outdir DIR             Output directory
  --break-bed-dir DIR      Directory with SAMPLE.deduplicated.bed files
      or
  --anno-dir DIR           Directory with SAMPLE.anno.bed files from bedtools intersect

Reference bin options:
  --gtf FILE               Build region bins from this GTF
  --region-bins FILE       Existing region bins BED
  --prefix NAME            Prefix for generated bins [GRCh38.Allgene]

Annotation extraction options, only for --anno-dir:
  --break-col-start N      First 1-based column of embedded break BED [14]
  --read-id-col N          1-based read-id column used for unique reads [17]

Other:
  --jobs N                 Number of samples processed concurrently [1]
  --force                  Rerun all steps even when checkpoint markers exist
  -h, --help               Show this help

Outputs:
  ref/NAME.region_bins.bed
  result_file/SAMPLE.bin_counts.bed
  summary/SAMPLE.transcript_bin_counts.tsv
  summary/SAMPLE.region_bin_mean.tsv
  region_bin_mean_matrix.tsv
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

SAMPLE_LIST=""
OUTDIR=""
BREAK_BED_DIR=""
ANNO_DIR=""
GTF=""
REGION_BINS=""
PREFIX="GRCh38.Allgene"
BREAK_COL_START=14
READ_ID_COL=17
JOBS=1
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sample-list) SAMPLE_LIST="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    --break-bed-dir) BREAK_BED_DIR="$2"; shift 2 ;;
    --anno-dir) ANNO_DIR="$2"; shift 2 ;;
    --gtf) GTF="$2"; shift 2 ;;
    --region-bins) REGION_BINS="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --break-col-start) BREAK_COL_START="$2"; shift 2 ;;
    --read-id-col) READ_ID_COL="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$OUTDIR" ]] || die "--outdir is required"
[[ -n "$SAMPLE_LIST" ]] || die "--sample-list is required"
[[ -f "$SAMPLE_LIST" ]] || die "Sample list not found: $SAMPLE_LIST"
[[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || die "--jobs must be a positive integer"

if [[ -n "$BREAK_BED_DIR" && -n "$ANNO_DIR" ]]; then
  die "Use only one of --break-bed-dir or --anno-dir"
fi
if [[ -z "$BREAK_BED_DIR" && -z "$ANNO_DIR" ]]; then
  die "One of --break-bed-dir or --anno-dir is required"
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${PYTHON:-python3}"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${PYTHON:-python}"
else
  die "Missing python3/python"
fi

require_cmd bedtools
require_cmd awk

REF_DIR="$OUTDIR/ref"
RESULT_DIR="$OUTDIR/result_file"
SUMMARY_DIR="$OUTDIR/summary"
LOG_DIR="$OUTDIR/logs"
STATE_DIR="$OUTDIR/.workflow"
mkdir -p "$REF_DIR" "$RESULT_DIR" "$SUMMARY_DIR" "$LOG_DIR" "$STATE_DIR"

step_marker() {
  local step="$1"
  printf '%s/%s.done\n' "$STATE_DIR" "$step"
}

step_done() {
  local step="$1"
  shift

  [[ "$FORCE" -eq 0 ]] || return 1
  [[ -s "$(step_marker "$step")" ]] || return 1

  local output
  for output in "$@"; do
    [[ -e "$output" ]] || return 1
  done
}

mark_step_done() {
  local step="$1"
  shift

  {
    printf 'step=%s\n' "$step"
    printf 'completed_at=%(%F %T)T\n' -1
    printf 'outputs=%s\n' "$*"
  } > "$(step_marker "$step")"
}

write_step_header() {
  local step="$1"
  printf '[%(%F %T)T] start %s\n' -1 "$step"
}

write_step_footer() {
  local step="$1"
  printf '[%(%F %T)T] complete %s\n' -1 "$step"
}

if [[ -z "$REGION_BINS" ]]; then
  [[ -n "$GTF" ]] || die "Provide --gtf or --region-bins"
  [[ -f "$GTF" ]] || die "GTF not found: $GTF"
  REGION_BINS="$REF_DIR/${PREFIX}.region_bins.bed"
  if step_done "build_region_bins" "$REGION_BINS"; then
    log "Skip transcript-region bins: $REGION_BINS"
  else
    log "Build transcript-region bins: $REGION_BINS"
    {
      write_step_header "build_region_bins"
      "$PYTHON_BIN" "$UTILS_DIR/make_gene_region_bins.py" \
        --gtf "$GTF" \
        --output-bins "$REGION_BINS"
      write_step_footer "build_region_bins"
    } > "$LOG_DIR/build_region_bins.log" 2>&1
    mark_step_done "build_region_bins" "$REGION_BINS"
  fi
else
  [[ -f "$REGION_BINS" ]] || die "Region bins BED not found: $REGION_BINS"
fi

locate_break_bed() {
  local sample="$1"
  local candidates=(
    "$BREAK_BED_DIR/${sample}.deduplicated.bed"
    "$BREAK_BED_DIR/${sample}.deduplicated_output.bed"
    "$BREAK_BED_DIR/${sample}.breaks.bed"
    "$BREAK_BED_DIR/${sample}.bed"
  )
  local path
  for path in "${candidates[@]}"; do
    if [[ -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

count_sample() {
  local sample="$1"
  local raw="$RESULT_DIR/${sample}.bin_counts.bed"
  local transcript="$SUMMARY_DIR/${sample}.transcript_bin_counts.tsv"
  local mean="$SUMMARY_DIR/${sample}.region_bin_mean.tsv"

  log "[$sample] count profile bins"
  if step_done "count_${sample}" "$raw" "$transcript" "$mean"; then
    log "[$sample] skip profile bins"
  else
    {
      write_step_header "count_${sample}"
      if [[ -n "$BREAK_BED_DIR" ]]; then
        local break_bed
        break_bed="$(locate_break_bed "$sample")" || die "Break BED not found for sample: $sample"
        bedtools intersect -a "$REGION_BINS" -b "$break_bed" -wa -c > "$raw"
      else
        local anno="$ANNO_DIR/${sample}.anno.bed"
        [[ -f "$anno" ]] || die "Annotation BED not found: $anno"
        awk -v c="$BREAK_COL_START" -v rid="$READ_ID_COL" '
          BEGIN{OFS="\t"}
          NF >= c + 5 {
            if (rid > 0 && $rid != "" && seen[$rid]++) next
            print $c, $(c+1), $(c+2), $(c+3), $(c+4), $(c+5)
          }
        ' "$anno" |
          awk 'BEGIN{OFS="\t"} NF==6 && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {print}' |
          bedtools intersect -a "$REGION_BINS" -b - -wa -c > "$raw"
      fi

      "$PYTHON_BIN" "$UTILS_DIR/summarize_region_bin_counts.py" \
        --counts-bed "$raw" \
        --sample "$sample" \
        --out-transcript "$transcript" \
        --out-mean "$mean"
      write_step_footer "count_${sample}"
    } > "$LOG_DIR/${sample}.profile_count.log" 2>&1
    mark_step_done "count_${sample}" "$raw" "$transcript" "$mean"
  fi
}

pids=()
while IFS= read -r sample || [[ -n "$sample" ]]; do
  [[ -n "$sample" ]] || continue
  [[ "$sample" =~ ^# ]] && continue

  if [[ "$JOBS" -eq 1 ]]; then
    count_sample "$sample"
  else
    count_sample "$sample" &
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
[[ "$status" -eq 0 ]] || exit "$status"

mean_files=()
while IFS= read -r sample || [[ -n "$sample" ]]; do
  [[ -n "$sample" ]] || continue
  [[ "$sample" =~ ^# ]] && continue
  mean_files+=("$SUMMARY_DIR/${sample}.region_bin_mean.tsv")
done < "$SAMPLE_LIST"

matrix="$OUTDIR/region_bin_mean_matrix.tsv"
if step_done "merge_profile_matrix" "$matrix"; then
  log "Skip profile matrix: $matrix"
else
  {
    write_step_header "merge_profile_matrix"
    "$PYTHON_BIN" "$UTILS_DIR/summarize_region_bin_counts.py" \
      --mean-files "${mean_files[@]}" \
      --out-matrix "$matrix"
    write_step_footer "merge_profile_matrix"
  } > "$LOG_DIR/merge_profile_matrix.log" 2>&1
  mark_step_done "merge_profile_matrix" "$matrix"
fi

log "Profile matrix written: $matrix"
