#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd -- "$SCRIPT_DIR/../utils" && pwd)"

usage() {
  cat <<'USAGE'
Build transcript-region bins for SSB metagene/profile plots.

Required:
  --gtf FILE               Gene annotation GTF

Optional:
  --outdir DIR             Output directory [Profiling_File2/Tmp]
  --prefix NAME            Output prefix [GRCh38.Allgene]
  --force                  Rerun even when checkpoint marker exists
  -h, --help               Show this help

Output:
  OUTDIR/PREFIX.region_bins.bed

For sample counting after bin generation, use:
  bash scripts/ssb_profile.sh --region-bins OUTDIR/PREFIX.region_bins.bed ...
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

GTF=""
OUTDIR="Profiling_File2/Tmp"
PREFIX="GRCh38.Allgene"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gtf) GTF="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$GTF" ]] || die "--gtf is required"
[[ -f "$GTF" ]] || die "GTF not found: $GTF"

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="${PYTHON:-python3}"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="${PYTHON:-python}"
else
  die "Missing python3/python"
fi

LOG_DIR="$OUTDIR/logs"
STATE_DIR="$OUTDIR/.workflow"
OUT_BINS="$OUTDIR/${PREFIX}.region_bins.bed"
MARKER="$STATE_DIR/build_region_bins.done"

mkdir -p "$OUTDIR" "$LOG_DIR" "$STATE_DIR"

if [[ "$FORCE" -eq 0 && -s "$MARKER" && -e "$OUT_BINS" ]]; then
  echo "Skip existing $OUT_BINS"
else
  {
    printf '[%(%F %T)T] start build_region_bins\n' -1
    "$PYTHON_BIN" "$UTILS_DIR/make_gene_region_bins.py" \
      --gtf "$GTF" \
      --output-bins "$OUT_BINS"
    printf '[%(%F %T)T] complete build_region_bins\n' -1
  } > "$LOG_DIR/build_region_bins.log" 2>&1
  {
    printf 'step=build_region_bins\n'
    printf 'completed_at=%(%F %T)T\n' -1
    printf 'outputs=%s\n' "$OUT_BINS"
  } > "$MARKER"
  echo "Wrote $OUT_BINS"
fi
