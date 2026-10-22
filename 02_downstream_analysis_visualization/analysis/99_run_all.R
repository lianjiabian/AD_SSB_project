# Portable entry point. Run from a project root with approved input files.
source('code/00_config.R')
args<-commandArgs(TRUE);mode<-if(length(args))sub('^--mode=','',args[1])else'full'
stopifnot(mode%in%c('full','processed','figures','package'))
run_stage<-function(script,env=character()){
 stopifnot(file.exists(file.path('code',script)));f<-path('logs',paste0(sub('[.]R$','',script),'.log'));cat('RUN',script,'log:',f,'\n');flush.console()
 status<-system2(file.path(R.home('bin'),'Rscript'),shQuote(file.path('code',script)),stdout=f,stderr=f,env=env)
 if(status!=0L)stop('Stage failed: ',script,'. Inspect ',f)
 logstage('master',paste('PASS',script))
}
run_stage('97_check_dependencies.R')
if(file.exists(path('audit/IMMUTABLE_INPUT_MANIFEST.tsv'))){z<-rd(path('audit/IMMUTABLE_INPUT_MANIFEST.tsv'));actual<-unname(tools::md5sum(path(z$relative_file)));if(anyNA(actual)||!identical(actual,z$md5))stop('Frozen inputs changed: start a NEW independent version; do not reuse model/count checkpoints.')}
if(mode=='full')for(s in c('01_clinical.R','02_rebuild_counts.R','02a_reference_audit.R'))run_stage(s)
if(mode%in%c('full','processed')){
 for(s in c('03_statistics.R','04_models.R','05_profile.R','06_clinical_QC261.R','07_enrichment.R'))run_stage(s)
 run_stage('07_enrichment.R',env='SSB_ENRICHMENT_SPACE=GENE')
}
if(mode%in%c('full','processed','figures')){
 for(s in c('08_figures.R','11_raw_matrix_excel.R','09b_references.R','09_documents.R','12_excel_source_and_statistics.R','14_input_and_data_manifest.R','10_quality_assurance.R'))run_stage(s)
}
run_stage('13_package_release.R')
logstage('pipeline',paste('PASS mode',mode))
