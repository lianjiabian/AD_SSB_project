#!/usr/bin/env bash
# Source only from run_upstream.sh. Replace paths when moving servers.
FASTQ_DIR="${SSB_FASTQ_ROOT:-/inputs/raw_fastq}"
REFERENCE_DIR="${SSB_REFERENCE_ROOT:-/inputs/reference/GRCh38.p14.R48_20250509}"
SSB_ENV_PREFIX="${SSB_ENV_PREFIX:-/opt/conda/envs/ssb-atlas-v2}"
SAMPLE_LIST="${SSB_SAMPLE_LIST:-}"
OUTPUT_ROOT="${SSB_UPSTREAM_OUTPUT:-$SCRIPT_ROOT/../work/upstream}"
THREADS_PER_COMMAND="${SSB_THREADS_PER_COMMAND:-9}"
JOBS=1
PROFILE_JOBS=30
