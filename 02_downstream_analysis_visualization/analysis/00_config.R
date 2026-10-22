options(stringsAsFactors=FALSE)
ROOT <- Sys.getenv('SSB_PROJECT_ROOT',unset=normalizePath(getwd()))
PROJECT <- dirname(ROOT)
PREVIOUS <- file.path(PROJECT,'CI_atlas_integrated_release_20260927')
REFERENCE <- Sys.getenv('SSB_REFERENCE_ROOT',unset='/inputs/reference/GRCh38.p14.R48_20250509')
RUN <- Sys.getenv('SSB_UPSTREAM_ROOT',unset='/inputs/ssb_upstream/ssb_run')
PROFILE <- Sys.getenv('SSB_PROFILE_ROOT',unset='/inputs/ssb_upstream/Profiling_File2')
.libPaths(c(file.path(PROJECT,'CI_atlas_revision_20260915/runtime/R_library'),file.path(PROJECT,'NOA_R_rebuild_20260821/R_library'),file.path(PROJECT,'runtime/R_libs'),.libPaths()))
suppressPackageStartupMessages({library(data.table);library(matrixStats)})
setDTthreads(1L);Sys.setenv(OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',MKL_NUM_THREADS='1')
fontconfig_library<-Sys.getenv('SSB_FONTCONFIG_LIBRARY',unset=file.path(PROJECT,'runtime/wgcna_env/lib/libfontconfig.so.1'));if(file.exists(fontconfig_library))Sys.setenv(LD_PRELOAD=fontconfig_library)
SEED <- 20261013L;set.seed(SEED)
PRIMARY_SPACE <- 'EXON'
EXPECTED_N <- 261L
SPACES <- c('GENE','TSS200','INTRON','EXON')
for(d in c('code/panels','metadata','matrices','reference','results/differential','results/models','results/profile','results/enrichment','results/sensitivity','results/clinical','results/stage','source_data','figures/panels','figures/main','figures/supplementary','figures/review','tables','manuscript','logs','audit','checkpoints/counts','INTERNAL_RESTRICTED/original_clinical','GITHUB_READY'))dir.create(file.path(ROOT,d),recursive=TRUE,showWarnings=FALSE)
Sys.chmod(file.path(ROOT,'INTERNAL_RESTRICTED'),'0700')
rd <- function(p) fread(p,na.strings=c('NA',''),showProgress=FALSE)
wr <- function(x,p){dir.create(dirname(p),recursive=TRUE,showWarnings=FALSE);fwrite(x,p,sep='\t',na='NA')}
path <- function(...)file.path(ROOT,...)
clean <- function(x){x<-trimws(as.character(x));x[x%in%c('','/','NA','N/A','无','不能配合','无法配合')]<-NA_character_;x}
num <- function(x)suppressWarnings(as.numeric(clean(x)))
logstage <- function(stage,message){cat(format(Sys.time()),stage,message,'\n');z<-data.table(time=format(Sys.time()),stage=stage,message=message);wr(z,path('audit','last_progress.tsv'));fwrite(z,path('logs','stage_events.tsv'),sep='\t',append=file.exists(path('logs','stage_events.tsv')))}
savebook <- function(tabs,file){w<-openxlsx::createWorkbook();openxlsx::modifyBaseFont(w,fontName='Arial',fontSize=10);for(n in names(tabs)){z<-as.data.frame(tabs[[n]]);openxlsx::addWorksheet(w,n);openxlsx::writeData(w,n,z,withFilter=nrow(z)>0);openxlsx::freezePane(w,n,firstRow=TRUE,firstCol=TRUE);openxlsx::setColWidths(w,n,seq_len(ncol(z)),widths=22);openxlsx::addStyle(w,n,openxlsx::createStyle(fgFill='#3C5488',fontColour='white',textDecoration='bold',wrapText=TRUE),rows=1,cols=seq_len(ncol(z)),gridExpand=TRUE);openxlsx::setRowHeights(w,n,1,36)};openxlsx::saveWorkbook(w,file,overwrite=TRUE)}
G3 <- c('HC','Core 1-positive AD pathology','Core 1-negative cognitive disorders')
COL <- c('HC'='#3C5488','Disease-source'='#C17C3B','Core 1-positive AD pathology'='#8064A2','Core 1-negative cognitive disorders'='#E69F00','Core 1 unavailable'='#8A8A8A','Other eligible record'='#A6A6A6')
REGIONS <- c('up5k_2k','up2k_1k','up1k_200','up200_TSS','first_exon','first_intron','internal_exons','internal_introns','last_exon','down200_TES','down1k_200','down2k_1k','down5k_2k')
NB <- c(10,10,10,10,10,20,10,20,10,10,10,10,10)
BINMAP <- rbindlist(lapply(seq_along(REGIONS),function(i)data.table(region=REGIONS[i],bin=seq_len(NB[i]),region_index=i)));BINMAP[,position:=seq_len(.N)]
