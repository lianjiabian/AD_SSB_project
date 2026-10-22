source('code/00_config.R')
txmap<-fread(file.path(REFERENCE,'GRCh38.p14.v48.tranType.txt'),header=FALSE,col.names=c('tx','tx_type','gene_id','gene_name','gene_type'))
cache<-readRDS(path('reference/nonredundant_intervals.rds'));out<-list()
for(s in SPACES){
 if(s=='GENE')a<-fread(file.path(REFERENCE,'SSB_bed/GRCh38.p14.v48.per_g.bed'),header=FALSE,select=1:4,col.names=c('chrom','start','end','gene_id')) else if(s=='TSS200')a<-fread(file.path(REFERENCE,'SSB_bed/GRCh38.p14.v48.per_t.tss_add200.bed'),header=FALSE,select=c(1,2,3,8),col.names=c('chrom','start','end','gene_id')) else {a<-fread(file.path(REFERENCE,paste0('SSB_bed/GRCh38.p14.v48.per_t.',tolower(s),'.bed')),header=FALSE,select=1:4,col.names=c('chrom','start','end','tx'));a[,gene_id:=txmap$gene_id[match(sub(';+$','',tx),txmap$tx)]];a[,tx:=NULL]}
 stopifnot(!anyNA(a));nz<-sum(a$start==a$end);nraw<-nrow(a);if(s!='TSS200'){stopifnot(all(a$start>=1));a[,start:=start-1L]};bad<-a[end<=start];a<-a[end>start];setorder(a,gene_id,chrom,start,end);a[,block:=cumsum(start>shift(cummax(as.double(end)),fill=-Inf)),by=.(gene_id,chrom)];u<-a[,.(start=min(start),end=max(end)),by=.(gene_id,chrom,block)][,block:=NULL]
 saved<-rd(path('reference',paste0(s,'_gene_union_intervals.tsv')))[,.(gene_id,chrom,start,end)];setorder(saved,gene_id,chrom,start,end);setorder(u,gene_id,chrom,start,end);stopifnot(isTRUE(all.equal(u[,.(gene_id,chrom,start,end)],saved,check.attributes=FALSE)))
 wr(data.table(region=s,original_zero_width=nz,empty_intervals_excluded=nrow(bad),coordinate_rule=if(s=='TSS200')'Existing BED 401-bp TSS windows'else '1-based closed -> start minus one; end unchanged',cached_union_rebuilt_comparison='PASS'),path('audit',paste0(s,'_coordinate_conversion.tsv')))
 r<-cache[[s]];g<-rbindlist(r$global);b<-rbindlist(r$ambiguous);out[[s]]<-data.table(region=s,input_intervals=nraw,gene_union_intervals=nrow(u),genes=nrow(r$annotation),annotated_genes=sum(r$annotation$region_length_bp>0),summed_gene_bp=sum(r$annotation$region_length_bp),global_nonredundant_bp=sum(g$end-g$start),shared_bp=sum(b$end-b$start),status='PASS')
}
wr(rbindlist(out),path('audit/reference_union_qc.tsv'))
ip<-data.table(sample_id=readRDS(path('metadata/analysis_metadata.rds'))$sample_id);ip[,source:=path('results/profile/exact_count_inputs',paste0(sample_id,'.rds'))];ip[,md5:=unname(tools::md5sum(source))];stopifnot(!anyNA(ip$md5));wr(ip,path('audit/profile_exact_integer_inputs.tsv'))
logstage('reference_audit','PASS fresh source-coordinate union reconstruction agrees with cached intervals in all four regions')
