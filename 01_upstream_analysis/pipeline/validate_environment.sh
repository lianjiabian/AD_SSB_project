#!/usr/bin/env bash
set -euo pipefail

project="/opt/ssb-pipeline"
env_prefix="/opt/conda/envs/ssb-atlas-v2"
source "${project}/resources.env.sh"

require_file() {
  [[ -r "$1" && -s "$1" ]] || {
    echo "Missing or unreadable SSB resource: $1" >&2
    exit 1
  }
}

require_executable() {
  [[ -x "$1" ]] || {
    echo "Missing SSB executable: $1" >&2
    exit 1
  }
}

for tool in python bwa samtools bedtools fastqc multiqc pigz; do
  require_executable "${env_prefix}/bin/${tool}"
done

"${env_prefix}/bin/python" - <<'PY'
import pyfaidx
print(f"pyfaidx {pyfaidx.__version__}: PASS")
PY

for path in \
  "${SSB_REFERENCE_FASTA}" \
  "${SSB_REFERENCE_FAI}" \
  "${SSB_GTF}" \
  "${SSB_GFF3}" \
  "${SSB_GENE_BED}" \
  "${SSB_TRANSCRIPT_BED}" \
  "${SSB_TSS_BED}" \
  "${SSB_EXON_BED}" \
  "${SSB_INTRON_BED}" \
  "${SSB_REPEATMASKER_BED}"; do
  require_file "${path}"
done
for suffix in amb ann bwt pac sa; do
  require_file "${SSB_BWA_PREFIX}.${suffix}"
done

[[ "$(readlink -f "${SSB_REFERENCE_FASTA}")" == \
   /inputs/reference/Gencode/GRCh38.p14.R48_20250509/* ]] || {
  echo "SSB bundle does not resolve to the canonical shared GENCODE resource" >&2
  exit 1
}

PATH="${env_prefix}/bin:${PATH}" bash "${project}/scripts/utils/check_env.sh"
echo "SSB environment and shared reference bundle: PASS"
