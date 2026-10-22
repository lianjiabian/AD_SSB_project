#!/usr/bin/env bash
set -euo pipefail

required=(samtools bedtools awk sort)
aligners=(bwa bwa-mem2)
optional=(fastqc multiqc fastp seqkit pigz parallel shellcheck)

missing=0

echo "Required tools"
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
  printf '  OK      %-12s %s\n' "python3" "$PYTHON_BIN"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python)"
  printf '  OK      %-12s %s\n' "python" "$PYTHON_BIN"
else
  printf '  MISSING %-12s\n' "python3/python"
  missing=1
fi

for tool in "${required[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  OK      %-12s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '  MISSING %-12s\n' "$tool"
    missing=1
  fi
done

echo
echo "Aligner"
aligner_found=0
for tool in "${aligners[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  OK      %-12s %s\n' "$tool" "$(command -v "$tool")"
    aligner_found=1
  else
    printf '  MISSING %-12s\n' "$tool"
  fi
done
if [[ "$aligner_found" -eq 0 ]]; then
  missing=1
fi

echo
echo "Optional tools"
for tool in "${optional[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  OK      %-12s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '  MISSING %-12s\n' "$tool"
  fi
done

echo
if [[ -n "$PYTHON_BIN" ]]; then
  if ! "$PYTHON_BIN" - <<'PY'
import importlib.util
import sys
print("Python modules")
missing = False
for name in ["pyfaidx"]:
    state = "OK" if importlib.util.find_spec(name) else "MISSING"
    print(f"  {state:<7} {name}")
    missing = missing or state == "MISSING"
sys.exit(1 if missing else 0)
PY
  then
    missing=1
  fi
else
  echo "Python modules"
  echo "  SKIPPED python3/python is missing"
fi

if [[ "$missing" -ne 0 ]]; then
  echo
  echo "Environment is not ready. Create it with: conda env create -f environment.yml"
  exit 1
fi

echo
echo "Environment preflight passed."
