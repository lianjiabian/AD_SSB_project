# Independent R reconstruction when validated integer profile inputs are absent.
source('code/00_config.R')
m<-readRDS(path('metadata/analysis_metadata.rds'));target<-path('results/profile/exact_count_inputs');dir.create(target,showWarnings=FALSE)
f<-file.path(PROFILE,'Tmp/GRCh38.p14.v48.region_bins.bed');stopifnot(file.exists(f))
wfile<-path('reference/profile_integer_interval_weights.rds')
if(!file.exists(wfile)){b<-fread(f,header=FALSE,col.names=c('chrom','start','end','tx','gene_id','strand','region','bin'),showProgress=FALSE);stopifnot(all(b$end>b$start));ex<-b[,.(annotation_bp=sum(as.double(end-start)),transcript_bins=uniqueN(tx)),by=.(region,bin)];wr(ex,path('results/profile/annotation_exposure.tsv'));b<-merge(b,BINMAP,by=c('region','bin'));w<-b[,.(weight=.N),by=.(chrom,start,end,position)];saveRDS(split(w,by='chrom',keep.by=FALSE),wfile,compress=FALSE);wr(data.table(source=f,md5=unname(tools::md5sum(f)),intervals=nrow(b)),path('audit/profile_reference_manifest.tsv'));rm(b,w);gc()}
w<-readRDS(wfile);ex<-rd(path('results/profile/annotation_exposure.tsv'))
one<-function(id){out<-file.path(target,paste0(id,'.rds'));if(file.exists(out))return(TRUE);b<-fread(file.path(RUN,'5_Dedup_Bed',paste0(id,'.deduplicated.bed')),header=FALSE,select=c(1,2,6),col.names=c('chrom','position','strand'),showProgress=FALSE);b<-unique(b);counts<-numeric(150)
 for(ch in intersect(unique(b$chrom),names(w))){p<-sort(b[chrom==ch,position]);a<-w[[ch]];n<-findInterval(a$end-1,p)-findInterval(a$start-1,p);s<-rowsum(n*a$weight,a$position,reorder=FALSE);counts[as.integer(rownames(s))]<-counts[as.integer(rownames(s))]+s[,1]}
 z<-merge(BINMAP,ex,by=c('region','bin'));setorder(z,position);z[,`:=`(sample_id=id,count=counts)];saveRDS(z,out,compress=FALSE);TRUE}
a<-parallel::mclapply(m$sample_id,one,mc.cores=6L,mc.preschedule=FALSE);stopifnot(!any(vapply(a,inherits,logical(1),'try-error')))
