#!/usr/bin/env Rscript
# Safe orchestration. Original scientific scripts are copied, never sourced in
# their historical output directory. Without --execute this script only plans.
args_all <- commandArgs(FALSE)
script <- sub('^--file=', '', args_all[grepl('^--file=', args_all)])[1]
code_root <- dirname(normalizePath(script, mustWork=TRUE))
bundle <- dirname(code_root)
source(file.path(code_root, 'config.R'))
.libPaths(c(cfg$extra_R_libraries, .libPaths()))
Sys.setenv(R_LIBS=paste(.libPaths(), collapse=.Platform$path.sep),
           OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1', MKL_NUM_THREADS='1')
args <- commandArgs(TRUE)
stage <- if(length(args) && !startsWith(args[1], '--')) args[1] else 'check'
value <- function(key, default) {
  z <- args[startsWith(args, paste0('--', key, '='))]
  if(length(z)>1L) stop('Repeated option: ', key)
  if(length(z)) sub(paste0('^--', key, '='), '', z) else default
}
allowed <- c('check','prepare','quantify','statistics','base-figures','presentation','latest-figures','all')
if(stage %in% c('-h','--help') || '--help' %in% args) {
  cat('Usage: bash run.sh STAGE [--execute] [--out=/absolute/new/path]\n',
      'STAGE: ', paste(allowed, collapse=', '), '\n',
      'Optional presentation input: --analysis-root=...; latest input: --presentation-root=...\n', sep='')
  quit(status=0)
}
stopifnot(stage %in% allowed)
unknown <- args[startsWith(args,'--') & !args %in% '--execute' &
                  !grepl('^--(out|analysis-root|presentation-root)=', args)]
if(length(unknown)) stop('Unknown arguments: ', paste(unknown,collapse=', '))
execute <- '--execute' %in% args
out <- normalizePath(value('out', file.path(bundle,'work/downstream')), mustWork=FALSE)
analysis <- file.path(out, 'analysis')
presentation <- file.path(out, 'presentation')
baseline <- normalizePath(value('analysis-root', cfg$approved_analysis), mustWork=FALSE)
presentation_input <- normalizePath(value('presentation-root', cfg$approved_presentation), mustWork=FALSE)
required_private <- c(
 'INTERNAL_RESTRICTED/original_clinical/AD复核_多层级标签_最终人工复核版.csv',
 'INTERNAL_RESTRICTED/original_clinical/Codex_SSB_Core1_最终分析与写作提示_v4_最终人工复核.md',
 'INTERNAL_RESTRICTED/original_clinical/SSB_three_group_sample_list.tsv',
 'INTERNAL_RESTRICTED/analysis_inputs/QC303_technical_linkage.tsv',
 'INTERNAL_RESTRICTED/analysis_inputs/HC_QC144_observed.tsv',
 'INTERNAL_RESTRICTED/analysis_inputs/Laboratory_dictionary.tsv')
check <- function() {
  need <- c('data.table','matrixStats','IRanges','S4Vectors','limma','glmnet','Matrix',
            'ggplot2','patchwork','svglite','ragg','openxlsx','officer','rvg','flextable',
            'xml2','httr','jsonlite','stringr','png','zip','systemfonts')
  ok <- vapply(need, requireNamespace, logical(1), quietly=TRUE)
  cat('R packages:\n'); print(data.frame(package=need, installed=ok), row.names=FALSE)
  checks_file<-Sys.getenv('SSB_REVIEW_CHECKS_FILE')
  stopifnot(nzchar(checks_file),file.exists(checks_file),nzchar(Sys.getenv('SSB_DISCORDANT_SAMPLE_ID')))
  cat('Private adjudication rules and sensitivity identifier supplied externally.\n')
  files <- c(file.path(cfg$approved_analysis, required_private),
    file.path(cfg$profile,'Tmp/GRCh38.p14.v48.region_bins.bed'),
    file.path(cfg$reference,'GRCh38.p14.v48.tranType.txt'),
    file.path(cfg$approved_presentation,'mapping_and_QC/figure_registry.rds'))
  cat('\nInput prerequisites (no clinical contents printed):\n')
  print(data.frame(file=files, exists=file.exists(files)), row.names=FALSE)
  bins <- c('pdfinfo','pdffonts','pdftotext','identify','convert','zip','unzip')
  cat('\nExternal export/QA tools:\n');print(data.frame(tool=bins,path=unname(Sys.which(bins))),row.names=FALSE)
  sf <- systemfonts::match_fonts('Arial')$path
  cat('\nArial resolved to: ', sf, '\n', sep='')
  if(!all(ok) || !all(file.exists(files)) || any(!nzchar(Sys.which(bins))))
    stop('Preflight failed; see missing prerequisites above')
  if(!grepl('Arial', sf, ignore.case=TRUE)) stop('Arial is not installed; no silent substitution')
  z <- file.path(cfg$approved_analysis, 'metadata/final_group_list.tsv')
  m <- data.table::fread(z, showProgress=FALSE)
  stopifnot(nrow(m)==261L, !anyDuplicated(m$sample_id),
    all(table(factor(m$group,levels=names(cfg$expected_cohort)))==cfg$expected_cohort))
  stopifnot(Sys.getenv('SSB_DISCORDANT_SAMPLE_ID') %in% m$sample_id)
  beds <- file.path(cfg$upstream,'5_Dedup_Bed',paste0(m$sample_id,'.deduplicated.bed'))
  stopifnot(all(file.exists(beds)))
  cat('\nPASS: 261 unique participants, HC144/AD89/Other28; all 261 BEDs exist.\n')
  r <- system2(file.path(R.home('bin'),'Rscript'), shQuote(file.path(code_root,'analysis/96_metric_unit_tests.R')), stdout=TRUE,stderr=TRUE)
  cat(paste(r,collapse='\n'),'\n'); if(!is.null(attr(r,'status'))) stop('Synthetic metric test failed')
}
if(stage=='check') {check();quit(status=0)}
cat('PLAN: stage=',stage,'\nOutput=',out,'\nApproved clinical inputs=',cfg$approved_analysis,
    '\nStatistical scripts=',file.path(code_root,'analysis'),
    '\nLatest layouts=Fig2 / Fig3 / Fig4_square_axes / S18\n',sep='')
if(!execute) {cat('No analysis started. Add --execute to run.\n');quit(status=0)}
if(!startsWith(out,'/')) stop('Output must be absolute')
protected <- normalizePath(c('/','/data','/work',cfg$study,cfg$approved_analysis,
                             cfg$approved_presentation,cfg$reference,cfg$upstream,cfg$profile),mustWork=FALSE)
if(out %in% protected || any(startsWith(out,paste0(protected[-(1:4)],'/')))) stop('Protected output path')
marker <- file.path(out,'.SSB_REPRO_DOWNSTREAM')
if(dir.exists(out) && length(list.files(out,all.files=TRUE,no..=TRUE)) && !file.exists(marker))
  stop('Output must be empty/new, or created by this entry point')
dir.create(out,recursive=TRUE,showWarnings=FALSE);file.create(marker)
dir.create(file.path(out,'logs'),showWarnings=FALSE)
copy_file <- function(from,to) {
  if(!file.exists(from)) stop('Missing input: ',from)
  dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE)
  if(!file.exists(to)) stopifnot(file.copy(from,to,copy.date=TRUE))
}
copy_tree <- function(from,to,pattern=NULL) {
  if(!dir.exists(from)) stop('Missing directory: ',from)
  ff <- list.files(from,full.names=FALSE,recursive=TRUE,all.files=TRUE,no..=TRUE,pattern=pattern)
  ff <- ff[!file.info(file.path(from,ff))$isdir]
  for(f in ff) copy_file(file.path(from,f),file.path(to,f))
}
run_file <- function(file,wd,extra_env=character()) {
  log <- file.path(out,'logs',paste0(format(Sys.time(),'%Y%m%d_%H%M%S'),'_',basename(file),'.log'))
  cat('RUN ',file,'\nLOG ',log,'\n',sep='');flush.console()
  oldwd <- getwd();setwd(wd);on.exit(setwd(oldwd))
  status <- system2(file.path(R.home('bin'),'Rscript'), shQuote(file),
                    stdout=log,stderr=log,env=extra_env)
  if(status!=0L) stop('Stage failed; inspect ',log)
}
patch_file <- function(f, replacements) {
  txt <- readLines(f,warn=FALSE)
  for(old in names(replacements)) txt <- gsub(old,replacements[[old]],txt,fixed=TRUE)
  writeLines(txt,f,useBytes=TRUE)
}
prepare <- function() {
  copy_tree(file.path(code_root,'analysis'),file.path(analysis,'code'))
  for(f in required_private) copy_file(file.path(cfg$approved_analysis,f),file.path(analysis,f))
  optional <- 'INTERNAL_RESTRICTED/original_clinical/AC.xlsx'
  if(file.exists(file.path(cfg$approved_analysis,optional)))copy_file(file.path(cfg$approved_analysis,optional),file.path(analysis,optional))
  copy_file(Sys.getenv('SSB_REVIEW_CHECKS_FILE'),file.path(analysis,'INTERNAL_RESTRICTED/analysis_inputs/Participant_review_checks.tsv'))
  Sys.setenv(SSB_REVIEW_CHECKS_FILE=file.path(analysis,'INTERNAL_RESTRICTED/analysis_inputs/Participant_review_checks.tsv'))
  Sys.chmod(file.path(analysis,'INTERNAL_RESTRICTED'),'0700')
  # Only path portability changes. Counts, thresholds and model expressions stay unchanged.
  f <- file.path(analysis,'code/00_config.R')
  patch_file(f,c('PROJECT <- dirname(ROOT)'="PROJECT <- Sys.getenv('SSB_STUDY_ROOT',unset=dirname(ROOT))"))
  patch_file(file.path(analysis,'code/14_input_and_data_manifest.R'),
    c("rawdir<-'/inputs/raw_fastq'"="rawdir<-Sys.getenv('SSB_FASTQ_ROOT','/inputs/raw_fastq')"))
  invisible(TRUE)
}
set_analysis_env <- function() Sys.setenv(SSB_PROJECT_ROOT=analysis, SSB_STUDY_ROOT=cfg$study,
  SSB_REFERENCE_ROOT=cfg$reference,SSB_UPSTREAM_ROOT=cfg$upstream,
  SSB_PROFILE_ROOT=cfg$profile,SSB_FASTQ_ROOT=cfg$fastq)
astage <- function(f) run_file(file.path(analysis,'code',f),analysis)
quantify <- function() {
  astage('01_clinical.R');astage('02_rebuild_counts.R')
  # Fresh profile integers are generated before the audit that verifies their files.
  astage('05a_profile_from_BED.R');astage('02a_reference_audit.R')
}
statistics <- function() {
  for(f in c('03_statistics.R','04_models.R','05_profile.R','06_clinical_QC261.R'))astage(f)
  Sys.setenv(SSB_ENRICHMENT_SPACE='EXON');astage('07_enrichment.R')
  Sys.setenv(SSB_ENRICHMENT_SPACE='GENE');astage('07_enrichment.R');Sys.unsetenv('SSB_ENRICHMENT_SPACE')
}
base_figures <- function() {
  for(f in c('08_figures.R','11_raw_matrix_excel.R','09b_references.R','09_documents.R',
             '12_excel_source_and_statistics.R','14_input_and_data_manifest.R',
             '10_quality_assurance.R','13_package_release.R'))astage(f)
}
build_presentation <- function(base) {
  Sys.setenv(SSB_PROJECT_ROOT=base, SSB_PPT_OUT=file.path(base,'PPT_assembly_20261015'))
  # An editable baseline deck is a required input to the lossless reorganization.
  copy_tree(file.path(code_root,'native_powerpoint'),file.path(base,'PPT_assembly_20261015'))
  run_file(file.path(code_root,'native_powerpoint/assemble_all_figures.R'),base)
  copy_file(file.path(base,'PPT_assembly_20261015/SSB_All_Figures_editable_20261015.pptx'),
    file.path(base,'FINAL_SUBMISSION_PACKAGE/PowerPoint/SSB_All_Figures_editable_20261015.pptx'))
  copy_tree(file.path(code_root,'presentation/R'),file.path(presentation,'R'))
  copy_tree(file.path(cfg$approved_presentation,'author_inputs'),file.path(presentation,'author_inputs'))
  Sys.setenv(SSB_REVISION_ROOT=presentation,SSB_BASELINE_ROOT=base)
  for(f in c('01_inventory_and_mapping.R','03_manuscript_and_legends.R','02_render_figures.R',
             '04_word_documents.R','05_powerpoint.R','07_audit_and_package.R'))
    run_file(file.path(presentation,'R',f),presentation)
}
latest <- function(src) {
  # Work on a fresh mirror, never in approved presentation output directories.
  dst <- file.path(out,'latest_presentation_inputs')
  for(d in c('R','mapping_and_QC','source_data/panels'))copy_tree(file.path(src,d),file.path(dst,d))
  copy_tree(file.path(src,'source_panels/originals'),file.path(dst,'source_panels/originals'),pattern='[.](rds|svg)$')
  copy_file(file.path(src,'main_figures/Main_figures_editable.pptx'),file.path(dst,'main_figures/Main_figures_editable.pptx'))
  for(ext in c('pdf','svg','png','tiff')) copy_file(file.path(src,'supplementary_figures',paste0('Supplementary_Figure_S18.',ext)),file.path(dst,'supplementary_figures',paste0('Supplementary_Figure_S18.',ext)))
  Sys.setenv(SSB_BASELINE_ROOT=if(stage=='all')analysis else baseline)
  names <- c('Figure2','Figure3','Figure4_previous','Figure4_square_axes','S18')
  paths <- setNames(file.path(out,'latest_layouts',names),names)
  src_original <- '/inputs/ssb_study/SSB_manuscript_reorganized_20261015/final_figure_package'
  origdirs <- c(Figure2='SSB_Figure2_layout_20261019',Figure3='SSB_Figure3_layout_20261019',
    Figure4_previous='SSB_Figure4_layout_20261019',Figure4_square_axes='SSB_Figure4_square_axes_20261022',S18='SSB_Figure_S18_legend_revision_20261018')
  execute_files <- c(Figure2='recompose_Figure2.R',Figure3='recompose_Figure3.R',Figure4_previous='recompose_Figure4.R',Figure4_square_axes='recompose_Figure4_square_axes.R',S18='modify_S18_legend_only.R')
  for(n in names) {
    wd <- paths[[n]]; copy_tree(file.path(code_root,'revisions',n,'R'),file.path(wd,'R'))
    ff <- list.files(file.path(wd,'R'),full.names=TRUE,pattern='[.]R$')
    replacements <- setNames(dst,src_original)
    # Longest paths first, including the S18 supplementary-figure path.
    replacements <- c(setNames(file.path(dst,'supplementary_figures'),paste0(src_original,'/supplementary_figures')),replacements)
    for(n2 in names)replacements <- c(replacements,setNames(paths[[n2]],file.path('/inputs/ssb_study',origdirs[[n2]])))
    for(f in ff)patch_file(f,replacements)
    run_file(file.path(wd,'R',execute_files[[n]]),wd)
    qa <- setdiff(list.files(file.path(wd,'R'),pattern='^(check_|verify_).*R$',full.names=TRUE),character())
    for(f in qa)run_file(f,wd)
  }
  writeLines(c('Latest outputs; not the intermediate Figure4_previous:',
    paste0('Figure 2: ',paths[['Figure2']],'/figures'),paste0('Figure 3: ',paths[['Figure3']],'/figures'),
    paste0('Figure 4: ',paths[['Figure4_square_axes']],'/figures'),paste0('S18: ',paths[['S18']],'/figures')),
    file.path(out,'LATEST_OUTPUTS.txt'))
}
check()
if(stage %in% c('prepare','quantify','statistics','base-figures','all')) {prepare();set_analysis_env()}
if(stage %in% c('quantify','all'))quantify()
if(stage %in% c('statistics','all'))statistics()
if(stage %in% c('base-figures','all'))base_figures()
if(stage=='presentation') {
  # Never write the historical approved baseline to generate a missing native deck.
  if(baseline==normalizePath(cfg$approved_analysis,mustWork=FALSE))
    stop('Use --analysis-root pointing to a new reproduced analysis root. For approved graphics use latest-figures.')
  build_presentation(baseline)
}
if(stage=='all')build_presentation(analysis)
if(stage %in% c('latest-figures','all'))latest(if(stage=='all')presentation else presentation_input)
cat('DONE ',stage,'\nOutput: ',out,'\n',sep='')
