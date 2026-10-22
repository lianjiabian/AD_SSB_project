source('code/00_config.R')
suppressPackageStartupMessages({library(IRanges);library(S4Vectors)})
m<-readRDS(path('metadata/participant_manifest.rds'))[included_A==TRUE];ids<-m$sample_id
union_intervals<-function(a){setorder(a,gene_id,chrom,start,end);a[,block:=cumsum(start>data.table::shift(cummax(as.numeric(end)),fill=-Inf)),by=.(gene_id,chrom)];a[,.(start=min(start),end=max(end)),by=.(gene_id,chrom,block)][,block:=NULL][]}
refcache<-path('reference/nonredundant_intervals.rds')
if(!file.exists(refcache)){
 txmap<-fread(file.path(REFERENCE,'GRCh38.p14.v48.tranType.txt'),header=FALSE,col.names=c('tx','tx_type','gene_id','gene_name','gene_type'))
 g<-fread(file.path(REFERENCE,'SSB_bed/GRCh38.p14.v48.per_g.bed'),header=FALSE,col.names=c('chrom','start','end','gene_id','score','strand','gene_type','gene_name'))
 ann<-g[,.(gene_name=gene_name[1],gene_type=gene_type[1],chromosomes=paste(sort(unique(chrom)),collapse=';'),strands=paste(sort(unique(strand)),collapse=';'),multiple_loci=uniqueN(chrom)>1),by=gene_id];setorder(ann,gene_id)
 refs<-list();qa<-list()
 for(s in SPACES){
  if(s=='GENE')a<-g[,.(chrom,start,end,gene_id)] else if(s=='TSS200')a<-fread(file.path(REFERENCE,'SSB_bed/GRCh38.p14.v48.per_t.tss_add200.bed'),header=FALSE,select=c(1,2,3,8),col.names=c('chrom','start','end','gene_id')) else {
   a<-fread(file.path(REFERENCE,paste0('SSB_bed/GRCh38.p14.v48.per_t.',tolower(s),'.bed')),header=FALSE,select=1:4,col.names=c('chrom','start','end','tx'));a[,gene_id:=txmap$gene_id[match(sub(';+$','',tx),txmap$tx)]];a[,tx:=NULL]
  }
  stopifnot(!anyNA(a),all(a$start>=0),all(a$end>=a$start),all(a$gene_id%in%ann$gene_id))
  original_n<-nrow(a)
  # Source GENE/EXON are 1-based closed GTF; INTRON is also 1-based closed:
  # [preceding exon end + 1, following exon start - 1], verified against GTF.
  # Convert all three with start -= 1; preserve genuine 1-bp exons and introns.
  old_zero<-sum(a$end==a$start)
  if(s%in%c('GENE','EXON','INTRON')){stopifnot(all(a$start>=1));a[,start:=start-1L]}
  empty<-a[end<=start];wr(empty,path('audit',paste0(s,'_empty_intervals_after_conversion.tsv')));a<-a[end>start]
  wr(data.table(region=s,original_zero_width=old_zero,empty_intervals_excluded=nrow(empty),coordinate_rule=if(s%in%c('GENE','EXON','INTRON'))'start -= 1; end unchanged; 1-based closed source confirmed against GTF'else 'Existing 401-bp TSS BED window retained'),path('audit',paste0(s,'_coordinate_conversion.tsv')))
  u<-union_intervals(a);u[,gene_index:=match(gene_id,ann$gene_id)]
  global<-list();safe<-list();amb<-list()
  for(ch in unique(u$chrom)){
   z<-u[chrom==ch];ir<-IRanges(z$start+1L,z$end);dj<-disjoin(ir,with.revmap=TRUE);rmv<-mcols(dj)$revmap
   n<-lengths(rmv);bad<-n>1L
   # Within-gene unions are non-overlapping; >1 covering interval therefore means >1 gene.
   amb[[ch]]<-data.table(chrom=ch,start=start(dj)[bad]-1L,end=end(dj)[bad])
   good<-!bad;gi<-vapply(as.list(rmv[good]),function(v)z$gene_index[v[1]],integer(1))
   safe[[ch]]<-data.table(chrom=ch,start=start(dj)[good]-1L,end=end(dj)[good],gene_index=gi)
   rr<-reduce(ir);global[[ch]]<-data.table(chrom=ch,start=start(rr)-1L,end=end(rr))
  }
  ss<-rbindlist(safe);aa<-rbindlist(amb);gg<-rbindlist(global)
  len<-u[,.(region_length_bp=sum(as.double(end-start))),by=gene_index]
  slen<-ss[,.(unshared_length_bp=sum(as.double(end-start))),by=gene_index]
  ga<-copy(ann);ga[,gene_index:=seq_len(.N)];ga<-merge(ga,len,by='gene_index',all.x=TRUE,sort=FALSE);ga<-merge(ga,slen,by='gene_index',all.x=TRUE,sort=FALSE);ga[is.na(region_length_bp),region_length_bp:=0];ga[is.na(unshared_length_bp),unshared_length_bp:=0];ga[,ambiguous_length_bp:=region_length_bp-unshared_length_bp];setorder(ga,gene_index)
  refs[[s]]<-list(union=split(u,by='chrom',keep.by=FALSE),safe=split(ss,by='chrom',keep.by=FALSE),global=split(gg,by='chrom',keep.by=FALSE),ambiguous=split(aa,by='chrom',keep.by=FALSE),annotation=ga)
  wr(ga,path('reference',paste0(s,'_gene_annotation_lengths.tsv')));wr(u,path('reference',paste0(s,'_gene_union_intervals.tsv')))
  qa[[s]]<-data.table(region=s,input_intervals=original_n,gene_union_intervals=nrow(u),genes=nrow(ann),annotated_genes=sum(ga$region_length_bp>0),summed_gene_bp=sum(ga$region_length_bp),global_nonredundant_bp=sum(gg$end-gg$start),shared_bp=sum(aa$end-aa$start))
  logstage('reference',paste(s,'union intervals',nrow(u)))
 }
 saveRDS(refs,refcache,compress=FALSE);wr(rbindlist(qa),path('audit/reference_union_qc.tsv'))
}
refs<-readRDS(refcache)
countint<-function(pos,a)if(!nrow(a))numeric() else findInterval(a$end-1,pos)-findInterval(a$start-1,pos)
one<-function(id){
 setDTthreads(1);target<-path('checkpoints/counts',paste0(id,'.rds'));if(file.exists(target))return(target)
 f<-file.path(RUN,'5_Dedup_Bed',paste0(id,'.deduplicated.bed'));st<-Sys.time();b<-fread(f,header=FALSE,select=c(1,2,3,6),col.names=c('chrom','start','end','strand'),showProgress=FALSE,nThread=1)
 stopifnot(all(b$end-b$start==1L),all(b$start>=0),all(b$strand%in%c('+','-')))
 input_rows<-nrow(b);b<-unique(b,by=c('chrom','start','strand'));D<-nrow(b);stopifnot(D>0)
 chr<-b[,.N,by=chrom];setorder(chr,chrom);ct<-safe<-fra<-list()
 positions<-lapply(split(b$start,b$chrom),sort)
 for(s in SPACES){
  r<-refs[[s]];c<-k<-numeric(nrow(r$annotation));ng<-na<-0
  for(ch in intersect(names(positions),names(r$union))){
   pos<-positions[[ch]];a<-r$union[[ch]];q<-countint(pos,a);z<-rowsum(q,a$gene_index,reorder=FALSE);c[as.integer(rownames(z))]<-c[as.integer(rownames(z))]+z[,1]
   a<-r$safe[[ch]];if(!is.null(a)&&nrow(a)){z<-rowsum(countint(pos,a),a$gene_index,reorder=FALSE);k[as.integer(rownames(z))]<-k[as.integer(rownames(z))]+z[,1]}
   ng<-ng+sum(countint(pos,r$global[[ch]]));a<-r$ambiguous[[ch]];if(!is.null(a))na<-na+sum(countint(pos,a))
  }
  stopifnot(all(c>=0),all(c<=D),all(k<=c),ng<=D)
  ct[[s]]<-as.integer(c);safe[[s]]<-as.integer(k);fra[[s]]<-data.table(sample_id=id,region=s,D=D,gene_annotation_count_sum=sum(c),global_region_unique_count=ng,ambiguous_unique_count=na,fraction=ng/D)
 }
 saveRDS(list(sample_id=id,D=D,input_rows=input_rows,duplicate_rows_removed=input_rows-D,counts=ct,unshared_counts=safe,fractions=rbindlist(fra),chromosome_counts=chr,source=f,seconds=as.numeric(difftime(Sys.time(),st,units='secs'))),target,compress=FALSE)
 cat('COUNT DONE',id,D,round(as.numeric(difftime(Sys.time(),st,units='secs')),1),'seconds\n');target
}
args<-commandArgs(TRUE);selected<-if(length(args))intersect(args,ids)else ids;stopifnot(length(selected)>0)
res<-parallel::mclapply(selected,one,mc.cores=min(12L,length(selected)),mc.preschedule=FALSE)
if(any(vapply(res,inherits,logical(1),'try-error')))stop('Count workers failed; no inference started')
if(length(selected)==length(ids)){
 z<-lapply(res,readRDS);D<-vapply(z,'[[',numeric(1),'D');stopifnot(length(D)==EXPECTED_N)
 den<-rbindlist(lapply(z,function(a)data.table(sample_id=a$sample_id,D=a$D,input_rows=a$input_rows,duplicate_rows_removed=a$duplicate_rows_removed,seconds=a$seconds,source_bed=a$source)))
 wr(den,path('metadata/library_denominators.tsv'));wr(rbindlist(lapply(z,function(a)cbind(data.table(sample_id=a$sample_id),a$chromosome_counts))),path('metadata/library_counts_by_chromosome.tsv'))
 fr<-rbindlist(lapply(z,'[[','fractions'));B<-mean(fr[region=='GENE',gene_annotation_count_sum]);fr[,`:=`(GENE_batch_mean=B,Ri=gene_annotation_count_sum/B)];wr(fr,path('results/regional_Ri_fractions.tsv'))
 for(s in SPACES){C<-do.call(cbind,lapply(z,function(a)a$counts[[s]]));U<-do.call(cbind,lapply(z,function(a)a$unshared_counts[[s]]));a<-refs[[s]]$annotation;rownames(C)<-rownames(U)<-a$gene_id;colnames(C)<-colnames(U)<-ids;L<-sweep(C,2,D,'/')*1e10
  stopifnot(all(is.finite(L)),all(C==floor(C)),identical(colnames(C),ids));a[,`:=`(detection_A=rowMeans(C>0),eligible_A=rowMeans(C>0)>=.2)];ib<-m$sample_id%in%readRDS(path('metadata/participant_manifest.rds'))[included_B==TRUE,sample_id];a[,`:=`(detection_B=rowMeans(C[,ib,drop=FALSE]>0),eligible_B=rowMeans(C[,ib,drop=FALSE]>0)>=.2)]
  saveRDS(list(counts=C,unshared_counts=U,lpkm=L,annotation=a,sample_id=ids,D=D,metric='nonredundant within-gene count * 1e10 / all-valid-BED D',Ri_denominator=B),path('matrices',paste0(s,'_inputs.rds')),compress=FALSE)
  wr(cbind(data.table(gene_id=a$gene_id,gene_name=a$gene_name),as.data.table(C)),path('matrices',paste0('SSB_counts_',tolower(s),'.tsv')));wr(cbind(data.table(gene_id=a$gene_id,gene_name=a$gene_name),as.data.table(L)),path('matrices',paste0('SSB_LPKM_',tolower(s),'.tsv')));wr(cbind(data.table(gene_id=a$gene_id,gene_name=a$gene_name),as.data.table(log2(L+1))),path('matrices',paste0('SSB_log2_LPKM_',tolower(s),'.tsv')));wr(a,path('matrices',paste0(s,'_feature_manifest.tsv')))
 }
 stopifnot(abs(mean(fr[region=='GENE',Ri])-1)<1e-12)
 m[,`:=`(D=den$D[match(sample_id,den$sample_id)],log10_D=log10(den$D[match(sample_id,den$sample_id)]))];m[,complete_primary:=complete.cases(age_years,sex,log10_D,polya_retention)];saveRDS(m,path('metadata/analysis_metadata.rds'));wr(m,path('metadata/analysis_metadata.tsv'))
 wr(data.table(n=length(ids),GENE_count_sum=sum(fr[region=='GENE',gene_annotation_count_sum]),GENE_mean_count=B,mean_GENE_Ri=mean(fr[region=='GENE',Ri]),duplicate_rows_removed=sum(den$duplicate_rows_removed),status='PASS'),path('audit/metric_validation.tsv'))
 capture.output(sessionInfo(),file=path('audit/R_sessionInfo.txt'));logstage('metrics',paste('PASS new count, LPKM and Ri; GENE denominator',format(B,digits=16)))
}
