# Only paths and execution settings. No source data is loaded here.
study <- Sys.getenv('SSB_STUDY_ROOT', '/inputs/ssb_study')
cfg <- list(
  study = study,
  approved_analysis = Sys.getenv('SSB_APPROVED_ANALYSIS_ROOT', file.path(study, 'SSB_QC261_EXON_primary_20261013')),
  approved_presentation = Sys.getenv('SSB_APPROVED_PRESENTATION_ROOT', file.path(study, 'SSB_manuscript_reorganized_20261015/final_figure_package')),
  reference = Sys.getenv('SSB_REFERENCE_ROOT', '/inputs/reference/GRCh38.p14.R48_20250509'),
  upstream = Sys.getenv('SSB_UPSTREAM_ROOT', '/inputs/ssb_upstream/ssb_run'),
  profile = Sys.getenv('SSB_PROFILE_ROOT', '/inputs/ssb_upstream/Profiling_File2'),
  fastq = Sys.getenv('SSB_FASTQ_ROOT', '/inputs/raw_fastq'),
  extra_R_libraries = c(
    file.path(study, 'SSB_QC261_EXON_primary_20261013/PPT_assembly_20261015/R_library'),
    file.path(study, 'CI_atlas_revision_20260915/runtime/R_library'),
    file.path(study, 'NOA_R_rebuild_20260821/R_library'), file.path(study, 'runtime/R_libs')),
  seed = 20261013L,
  expected_cohort = c(HC = 144L, AD = 89L, Other = 28L)
)
