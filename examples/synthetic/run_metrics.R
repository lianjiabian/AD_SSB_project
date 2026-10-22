# Synthetic, non-patient example; base R only.
argv<-commandArgs(FALSE);f<-sub('^--file=','',argv[grepl('^--file=',argv)])[1]
here<-dirname(normalizePath(f))
x<-read.delim(file.path(here,'counts.tsv'),check.names=FALSE)
lib<-read.delim(file.path(here,'library_totals.tsv'),check.names=FALSE)
stopifnot(!anyDuplicated(lib$sample_id),all(lib$D>0),all(grepl('^SYN',lib$sample_id)))
samples<-lib$sample_id;spaces<-c('GENE','EXON','INTRON','TSS200')
counts<-setNames(lapply(spaces,function(s){a<-x[x$region==s,];stopifnot(!anyDuplicated(a$gene_id));m<-as.matrix(a[,samples]);rownames(m)<-a$gene_id;stopifnot(all(m>=0),all(m==floor(m)));m}),spaces)
B<-mean(colSums(counts$GENE));stopifnot(B>0)
# Keep validation and normalization separate, with an explicit per-column D.
LPKM<-lapply(counts,function(C){stopifnot(all(sweep(C,2,lib$D,FUN=function(c,d)c<=d)));sweep(C,2,lib$D,'/')*1e10})
Y<-lapply(LPKM,function(L)log2(1+L))
Ri<-do.call(rbind,lapply(spaces,function(s)data.frame(region=s,sample_id=samples,
 count_total=colSums(counts[[s]]),GENE_denominator=B,Ri=colSums(counts[[s]])/B)))
stopifnot(abs(mean(Ri$Ri[Ri$region=='GENE'])-1)<1e-12,
          all(vapply(Y,function(y)all(is.finite(y)),logical(1))),
          LPKM$GENE[2,1]==0,Y$GENE[2,1]==0,
          all(Ri$GENE_denominator==B))
cat('SYNTHETIC EXAMPLE ONLY — no patient findings\n');print(Ri,row.names=FALSE)
cat('PASS: full-library LPKM, fixed shared GENE denominator, zeros and log signal\n')
