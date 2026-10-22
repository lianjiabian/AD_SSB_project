#!/usr/bin/env bash
set -euo pipefail
CODE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STUDY_ROOT="${SSB_STUDY_ROOT:-/inputs/ssb_study}"
R_BIN="${SSB_RSCRIPT:-$STUDY_ROOT/runtime/wgcna_env/bin/Rscript}"
if [[ ! -x "$R_BIN" ]]; then R_BIN="$(command -v Rscript)"; fi
NATIVE_LIB="$STUDY_ROOT/runtime/wgcna_env/lib"
if [[ -d "$NATIVE_LIB" ]]; then
  export LD_LIBRARY_PATH="$NATIVE_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  if [[ -f "$NATIVE_LIB/libfontconfig.so.1" ]]; then export LD_PRELOAD="$NATIVE_LIB/libfontconfig.so.1"; fi
fi
exec "$R_BIN" "$CODE_ROOT/run_reproduce.R" "$@"
