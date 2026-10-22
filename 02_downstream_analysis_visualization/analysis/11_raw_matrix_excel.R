source('code/00_config.R')
suppressPackageStartupMessages(library(openxlsx))
dir.create(path('excel/raw_matrices'),recursive=TRUE,showWarnings=FALSE)
make_matrix_book<-function(space){
  file<-path('excel/raw_matrices',paste0('SSB_',space,'_counts_and_LPKM.xlsx'))
  done<-path('audit',paste0('Excel_raw_',space,'_validation.tsv'))
  if(file.exists(file)&&file.exists(done)){cat(space,'already verified\n');return(TRUE)}
  cat(format(Sys.time()),'EXCEL START',space,'\n');flush.console()
  z<-readRDS(path('matrices',paste0(space,'_inputs.rds')))
  stopifnot(identical(colnames(z$counts),z$sample_id),ncol(z$counts)==EXPECTED_N,
            !anyNA(z$counts),!anyNA(z$lpkm),!anyDuplicated(z$annotation$gene_id))
  w<-createWorkbook();modifyBaseFont(w,fontName='Arial',fontSize=10)
  defs<-data.frame(item=c('Region','Orientation','Count definition','LPKM formula','D definition','Length normalization','Missing / zero','GENE Ri reference','Participants','Reference'),
    definition=c(space,'Genes in rows; SSB sequencing sample IDs in columns',
      'Unique chromosome-coordinate-strand positions within each gene-region union',
      'SSB_LPKM_ij = count_ij * 10^10 / D_j',
      'All positions in the complete valid deduplicated BED, including non-genic and non-primary contigs',
      'No additional gene/exon-length division; no TPM transformation',
      'Zero is a successfully computed non-detection; computation failures are not filled with zero',
      sprintf('Fixed QC261 mean of unfiltered GENE totals: %.12f',z$Ri_denominator),
      '261 (HC144; AD89; Other28)','GRCh38.p14; GENCODE v48'))
  addWorksheet(w,'Definitions');writeData(w,'Definitions',defs);setColWidths(w,'Definitions',1:2,widths=c(26,100));freezePane(w,'Definitions',firstRow=TRUE)
  headstyle<-createStyle(fgFill='#3C5488',fontColour='white',textDecoration='bold')
  for(nm in c('Counts','SSB_LPKM','Log2_1plus_LPKM')){
    addWorksheet(w,nm)
    mat<-if(nm=='Counts')z$counts else if(nm=='SSB_LPKM')z$lpkm else log2(z$lpkm+1)
    tab<-data.frame(gene_id=z$annotation$gene_id,gene_name=z$annotation$gene_name,
                    as.data.frame(mat,check.names=FALSE),check.names=FALSE)
    writeData(w,nm,tab,keepNA=TRUE,na.string='NA',withFilter=TRUE)
    addStyle(w,nm,headstyle,rows=1,cols=seq_len(ncol(tab)),gridExpand=TRUE)
    freezePane(w,nm,firstActiveRow=2,firstActiveCol=3)
    setColWidths(w,nm,1:2,widths=c(27,20));setColWidths(w,nm,3:ncol(tab),widths=15)
    rm(tab,mat);gc()
  }
  addWorksheet(w,'Gene_annotation');writeData(w,'Gene_annotation',as.data.frame(z$annotation),withFilter=TRUE);freezePane(w,'Gene_annotation',firstRow=TRUE)
  den<-rd(path('metadata/library_denominators.tsv'));clinical<-readRDS(path('metadata/analysis_metadata.rds'))
  den<-merge(den,clinical[,.(sample_id,source_group,pathology_group,included_A,included_B)],by='sample_id')
  addWorksheet(w,'Library_denominators');writeData(w,'Library_denominators',as.data.frame(den),withFilter=TRUE);freezePane(w,'Library_denominators',firstRow=TRUE)
  saveWorkbook(w,file,overwrite=TRUE);rm(w);gc()
  # Round-trip non-zero representative signals, not only zero-filled first rows.
  genes<-rd(path('results/representative_genes.tsv'))$gene_id
  gi<-sort(unique(match(genes,z$annotation$gene_id)));gi<-gi[!is.na(gi)]
  # Deterministic cell spot checks without publishing selected participant IDs.
  sj<-seq_len(min(3L,length(z$sample_id)))
  val<-list()
  for(nm in c('Counts','SSB_LPKM','Log2_1plus_LPKM')){
    back<-read.xlsx(file,sheet=nm,rows=c(1,gi+1),cols=c(1,2,sj+2),check.names=FALSE)
    stopifnot(identical(back$gene_id,z$annotation$gene_id[gi]))
    actual<-as.matrix(back[,z$sample_id[sj],drop=FALSE]);expected<-if(nm=='Counts')z$counts[gi,sj,drop=FALSE]else if(nm=='SSB_LPKM')z$lpkm[gi,sj,drop=FALSE]else log2(z$lpkm[gi,sj,drop=FALSE]+1)
    relative_error<-max(abs(actual-expected)/pmax(1,abs(expected)))
    stopifnot(relative_error<1e-12)
    val[[nm]]<-data.table(region=space,sheet=nm,genes=nrow(z$counts),participants=length(z$sample_id),
                         roundtrip_cells=length(expected),max_relative_error=relative_error,status='PASS')
  }
  wr(rbindlist(val),done);cat(format(Sys.time()),'EXCEL PASS',space,'\n');flush.console();TRUE
}
args<-commandArgs(TRUE);spaces<-if(length(args))intersect(args,SPACES)else SPACES
workers<-as.integer(Sys.getenv('SSB_EXCEL_WORKERS',unset='2'));workers<-max(1L,min(4L,workers))
ans<-parallel::mclapply(spaces,make_matrix_book,mc.cores=workers,mc.preschedule=FALSE)
if(any(vapply(ans,inherits,logical(1),'try-error')))stop('Raw matrix Excel export failed; inspect region logs/checks')
wr(rbindlist(lapply(SPACES,function(s)rd(path('audit',paste0('Excel_raw_',s,'_validation.tsv'))))),path('audit/Excel_raw_matrix_roundtrip.tsv'))
logstage('raw_excel','PASS four complete count/LPKM Excel matrices and nonzero-value round trips')
