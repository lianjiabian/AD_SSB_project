#!/usr/bin/env bash
# EXAMPLE ONLY: copy outside the repository and edit. Never commit real values.
export SSB_STUDY_ROOT="/inputs/ssb_study"
export SSB_APPROVED_ANALYSIS_ROOT="/inputs/ssb_study/SSB_QC261_EXON_primary_20261013"
export SSB_APPROVED_PRESENTATION_ROOT="/inputs/ssb_study/SSB_manuscript_reorganized_20261015/final_figure_package"
export SSB_REFERENCE_ROOT="/inputs/reference/GRCh38.p14.R48_20250509"
export SSB_UPSTREAM_ROOT="/inputs/ssb_upstream/ssb_run"
export SSB_PROFILE_ROOT="/inputs/ssb_upstream/Profiling_File2"
export SSB_FASTQ_ROOT="/inputs/raw_fastq"
export SSB_SAMPLE_LIST="/private/approved_upstream_sample_ids.txt"
export SSB_ENV_PREFIX="/opt/conda/envs/ssb-atlas-v2"
# Use an installed Rscript on PATH, or set SSB_RSCRIPT to its absolute path.
# Participant-specific controls must come from the authorized review record.
export SSB_REVIEW_CHECKS_FILE="/private/Participant_review_checks.tsv"
export SSB_DISCORDANT_SAMPLE_ID=""
# Independent writable outputs; never point these at original analysis roots.
export SSB_UPSTREAM_OUTPUT="/work/ssb_reproduction/upstream"
