#!/usr/bin/env bash
set -euo pipefail
SCRIPT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_ROOT/config.sh"
case "${1:---plan}" in
  --plan) execute=0 ;;
  --execute) execute=1 ;;
  -h|--help) echo 'Usage: bash run_upstream.sh [--plan|--execute]'; exit 0 ;;
  *) echo 'Unknown option' >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo 'Unexpected arguments' >&2; exit 2; }
[[ -f "$SAMPLE_LIST" && -d "$FASTQ_DIR" && -d "$REFERENCE_DIR" ]] || { echo 'Missing sample list, FASTQ directory or reference' >&2; exit 1; }
[[ "$THREADS_PER_COMMAND" =~ ^[1-9][0-9]*$ ]] || exit 2
export PATH="$SSB_ENV_PREFIX/bin:$PATH"
command=(bash "$SCRIPT_ROOT/pipeline/scripts/run_all.sh"
  --fastq-dir "$FASTQ_DIR" --ref-dir "$REFERENCE_DIR" --sample-list "$SAMPLE_LIST"
  --aligner bwa --threads "$THREADS_PER_COMMAND" --jobs "$JOBS" --profile-jobs "$PROFILE_JOBS"
  --mapq 20 --flag-r1 GGGGGGGGGG --flag-r2 TTTTTTTTTTTT --polya-window 40 --polya-cutoff 0.4
  --outdir "$OUTPUT_ROOT/ssb_run" --profile-outdir "$OUTPUT_ROOT/Profiling_File2")
printf 'PLAN: '; printf '%q ' "${command[@]}"; printf '\n'
(( execute )) || exit 0
resolved="$(realpath -m -- "$OUTPUT_ROOT")"
case "$resolved" in
  /|/data|/work|/mnt|/inputs/storage|/inputs/storage/Analysis|/inputs/ssb_upstream|/inputs/ssb_upstream/*)
    echo 'Refusing original/broad output directory' >&2; exit 1 ;;
esac
marker="$resolved/.SSB_REPRO_UPSTREAM"
if [[ -d "$resolved" && ! -f "$marker" ]] && [[ -n "$(ls -A -- "$resolved")" ]]; then
  echo 'Output must be new or created by this entry point' >&2; exit 1
fi
mkdir -p -- "$resolved"
touch "$marker"
"${command[@]}"
