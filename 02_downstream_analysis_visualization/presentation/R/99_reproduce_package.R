# Run from the delivered package root, or set SSB_REVISION_ROOT explicitly.
args<-commandArgs(FALSE);f<-args[startsWith(args,'--file=')]
if(length(f)&&!nzchar(Sys.getenv('SSB_REVISION_ROOT'))){root<-dirname(dirname(normalizePath(sub('--file=','',f[1],fixed=TRUE))));Sys.setenv(SSB_REVISION_ROOT=root);setwd(root)}
if(nzchar(Sys.getenv('SSB_REVISION_ROOT')))setwd(Sys.getenv('SSB_REVISION_ROOT'))
Sys.unsetenv(c('SSB_SINGLE_PANEL','SSB_RENDER_FIGURES','SSB_VECTOR_ONLY'))
if(!file.exists('mapping_and_QC/figure_registry.rds'))source('R/01_inventory_and_mapping.R')
source('R/03_manuscript_and_legends.R')
source('R/02_render_figures.R')
source('R/04_word_documents.R')
source('R/05_powerpoint.R')
source('R/07_audit_and_package.R')
source('R/08_preview_and_runtime_record.R')
cat('REPRODUCTION COMPLETE: presentation changes only; no statistical model rerun.\n')
