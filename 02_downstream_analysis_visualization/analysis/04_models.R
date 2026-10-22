source('code/00_config.R');suppressPackageStartupMessages(library(glmnet))
stopifnot(nzchar(Sys.getenv('SSB_DISCORDANT_SAMPLE_ID')))
m<-readRDS(path('metadata/analysis_metadata.rds'))[complete_primary==TRUE];m[,sex:=factor(sex,levels=c('Female','Male'))]
auc<-function(y,p){n1<-sum(y==1);n0<-sum(y==0);if(!n1||!n0)return(NA_real_);(sum(rank(p)[y==1])-n1*(n1+1)/2)/(n1*n0)}
folds<-function(y,k,seed,block=NULL){set.seed(seed);f<-integer(length(y));if(is.null(block)){for(g in unique(y)){ii<-sample(which(y==g));f[ii]<-rep(seq_len(k),length.out=length(ii))}}else{bb<-sample(unique(block));bmap<-setNames(rep(seq_len(k),length.out=length(bb)),bb);f<-as.integer(bmap[as.character(block)])};f}
prep<-function(tr,te,dtr,dte,kind){
 if(kind=='Ri'){ref<-mean(tr[,'GENE']);stopifnot(ref>0);tr<-log2(tr/ref+1);te<-log2(te/ref+1)}
 keep<-if(kind=='Molecular')colSums(is.finite(tr))==nrow(tr)&colSums(tr>0)>=ceiling(.2*nrow(tr)) else colSums(is.finite(tr))>0
 original<-which(keep);a<-tr[,keep,drop=FALSE];b<-te[,keep,drop=FALSE]
 if(any(!is.finite(a))||any(!is.finite(b))){med<-apply(a,2,median,na.rm=TRUE);for(j in seq_len(ncol(a))){a[!is.finite(a[,j]),j]<-med[j];b[!is.finite(b[,j]),j]<-med[j]}}
 if(kind!='Clinical'){u<-model.matrix(~age_years+sex+log10_D+polya_retention,dtr);v<-model.matrix(~age_years+sex+log10_D+polya_retention,dte);theta<-qr.solve(u,a);a<-a-u%*%theta;b<-b-v%*%theta}
 mu<-colMeans(a);ss<-colSds(a);good<-is.finite(ss)&ss>1e-8;original<-original[good];a<-a[,good,drop=FALSE];b<-b[,good,drop=FALSE]
 a<-sweep(sweep(a,2,mu[good],'-'),2,ss[good],'/');b<-sweep(sweep(b,2,mu[good],'-'),2,ss[good],'/')
 stopifnot(ncol(a)>=2,all(is.finite(a)),all(is.finite(b)));list(train=a,test=b,original=original)
}
rank_features<-function(x,y){v<-abs((colMeans(x[y==1,,drop=FALSE])-colMeans(x[y==0,,drop=FALSE]))/sqrt(colVars(x[y==1,,drop=FALSE])/sum(y==1)+colVars(x[y==0,,drop=FALSE])/sum(y==0)));v[!is.finite(v)]<-0;order(v,decreasing=TRUE)}
lambdas<-c(10,1,.1);ks<-c(10L,25L,50L)
ridge<-function(x,y,test){f<-glmnet(x,y,family='binomial',alpha=0,lambda=lambdas,standardize=FALSE,intercept=TRUE,thresh=1e-8);as.matrix(predict(f,newx=test,s=lambdas,type='response'))}
tasks<-CJ(task=c('source','pathology','exclude_discordant_record','AV45_only','matched'),region=SPACES)
tasks<-rbind(tasks,data.table(task='source',region=c('Ri','Clinical')))
run_task<-function(task,region){
 key<-paste(task,region,sep='_');done<-path('results/models',paste0(key,'_complete.rds'));if(file.exists(done))return(done)
 dm<-if(task=='source')copy(m) else m[included_B==TRUE & source_group=='Disease-source']
 if(task=='exclude_discordant_record')dm<-dm[sample_id!=Sys.getenv('SSB_DISCORDANT_SAMPLE_ID')]
 if(task=='AV45_only')dm<-dm[(pathology_group==G3[2]&av45_status=='阳性') | (pathology_group==G3[3]&av45_status=='阴性')]
 if(task=='matched'){pp<-readRDS(path('metadata/matched_pairs.rds'));dm<-merge(dm,pp[,.(sample_id,matched_pair)],by='sample_id',sort=FALSE)}
 dm[,target:=if(task=='source')case else as.integer(pathology_group==G3[2])]
 if(min(table(dm$target))<10){saveRDS(list(status='Insufficient class size for planned nested CV',task=task,region=region,n=nrow(dm)),done);return(done)}
 if(region%in%SPACES){z<-readRDS(path('matrices',paste0(region,'_inputs.rds')));xx<-t(log2(z$lpkm[,dm$sample_id,drop=FALSE]+1));geneids<-z$annotation$gene_id;rm(z);gc();kind<-'Molecular'} else if(region=='Ri'){r<-dcast(rd(path('results/regional_Ri_fractions.tsv')),sample_id~region,value.var='gene_annotation_count_sum');xx<-as.matrix(r[match(dm$sample_id,sample_id),..SPACES]);kind<-'Ri'} else {cv<-c('age_years','sex_male','wbc_10e9_l','neutrophil_pct','lymphocyte_pct','monocyte_pct','rbc_10e12_l','hemoglobin_g_l','hematocrit_pct','mcv_fl','platelet_10e9_l');xx<-as.matrix(dm[,..cv]);kind<-'Clinical'}
 predictions<-selected<-tuned<-split_audit<-list();counter<-0L
 for(rep in 1:5){block<-if(task=='matched')dm$matched_pair else NULL;outer<-folds(dm$target,5,SEED+rep+match(task,c('source','pathology','exclude_discordant_record','AV45_only','matched'))*100,block)
  for(f in 1:5){oi<-which(outer!=f);ov<-which(outer==f);inner<-folds(dm$target[oi],4,SEED+1000+rep*10+f,if(task=='matched')dm$matched_pair[oi]else NULL);kgrid<-if(kind=='Molecular')ks else ncol(xx);grid<-CJ(k=kgrid,lambda=lambdas);ip<-array(NA_real_,dim=c(length(oi),length(kgrid),length(lambdas)))
   for(j in 1:4){it<-oi[inner!=j];iv<-oi[inner==j];stopifnot(!length(intersect(dm$sample_id[it],dm$sample_id[iv])),!length(intersect(dm$sample_id[it],dm$sample_id[ov])));if(task=='matched')stopifnot(!length(intersect(dm$matched_pair[it],dm$matched_pair[ov])))
    pp<-prep(xx[it,,drop=FALSE],xx[iv,,drop=FALSE],dm[it],dm[iv],kind);rr<-if(kind=='Molecular')rank_features(pp$train,dm$target[it])else seq_len(ncol(pp$train))
    for(ki in seq_along(kgrid)){cols<-head(rr,kgrid[ki]);ip[which(inner==j),ki,]<-ridge(pp$train[,cols,drop=FALSE],dm$target[it],pp$test[,cols,drop=FALSE])}
    split_audit[[length(split_audit)+1]]<-data.table(task=task,region=region,repetition=rep,outer_fold=f,inner_fold=j,training_ids=paste(dm$sample_id[it],collapse='|'),validation_ids=paste(dm$sample_id[iv],collapse='|'),outer_test_ids=paste(dm$sample_id[ov],collapse='|'),features=ncol(pp$train),overlap=0L,matched_block_preserved=task=='matched')
   }
   for(i in seq_len(nrow(grid)))grid[i,AUC:=auc(dm$target[oi],ip[,match(k,kgrid),match(lambda,lambdas)])]
   best<-grid[order(-AUC,k,-lambda)][1];pp<-prep(xx[oi,,drop=FALSE],xx[ov,,drop=FALSE],dm[oi],dm[ov],kind);rr<-if(kind=='Molecular')rank_features(pp$train,dm$target[oi])else seq_len(ncol(pp$train));cols<-head(rr,best$k);prob<-ridge(pp$train[,cols,drop=FALSE],dm$target[oi],pp$test[,cols,drop=FALSE])[,match(best$lambda,lambdas)]
   counter<-counter+1;predictions[[counter]]<-data.table(sample_id=dm$sample_id[ov],task=task,region=region,repetition=rep,outer_fold=f,y=dm$target[ov],probability=prob);tuned[[counter]]<-cbind(data.table(task=task,region=region,repetition=rep,outer_fold=f),best)
   if(kind=='Molecular')selected[[counter]]<-data.table(task=task,region=region,repetition=rep,outer_fold=f,gene_id=geneids[pp$original[cols]],rank=seq_along(cols))
  };cat('CV',key,'repeat',rep,'done\n')
 }
 p<-rbindlist(predictions);stopifnot(!anyDuplicated(p[,.(sample_id,repetition)]),all(is.finite(p$probability)))
 wr(p,path('results/models',paste0(key,'_OOF.tsv')));wr(rbindlist(split_audit),path('audit',paste0(key,'_split_audit.tsv')));wr(rbindlist(tuned),path('results/models',paste0(key,'_tuning.tsv')));if(length(selected))wr(rbindlist(selected),path('results/models',paste0(key,'_features.tsv')))
 saveRDS(list(status='PASS',task=task,region=region,n=nrow(dm)),done);done
}
jobs<-split(tasks,seq_len(nrow(tasks)));ans<-parallel::mclapply(jobs,function(t)run_task(t$task,t$region),mc.cores=8L,mc.preschedule=FALSE)
if(any(vapply(ans,inherits,logical(1),'try-error')))stop('A CV task failed; completed task checkpoints preserved')
p<-rbindlist(lapply(list.files(path('results/models'),pattern='_OOF.tsv$',full.names=TRUE),rd));wr(p,path('results/models/all_OOF_predictions.tsv'))
avg<-p[,.(y=y[1],probability=mean(probability),predictions=.N),by=.(sample_id,task,region)];stopifnot(all(avg$predictions==5));wr(avg,path('results/models/participant_mean_OOF.tsv'))
repeat_metrics<-p[,.(n=.N,AUC=auc(y,probability),Brier=mean((y-probability)^2)),by=.(task,region,repetition)];wr(repeat_metrics,path('results/models/repeated_metrics.tsv'))
ap<-function(y,p){o<-order(p,decreasing=TRUE);yy<-y[o];ends<-cumsum(rle(p[o])$lengths);tp<-cumsum(yy)[ends];recall<-tp/sum(yy);precision<-tp/ends;sum(diff(c(0,recall))*precision)}
metrics<-avg[,{set.seed(SEED);bs<-replicate(2000,{ii<-c(sample(which(y==0),sum(y==0),replace=TRUE),sample(which(y==1),sum(y==1),replace=TRUE));auc(y[ii],probability[ii])});.(n=.N,positive=sum(y==1),negative=sum(y==0),AUC=auc(y,probability),CI_low=unname(quantile(bs,.025)),CI_high=unname(quantile(bs,.975)),Brier=mean((y-probability)^2),Average_precision=ap(y,probability),PR_baseline=mean(y),interval='Class-stratified participant bootstrap of fixed mean held-out probabilities')},by=.(task,region)]
wr(metrics,path('results/models/performance.tsv'))
cal<-avg[,{br<-unique(quantile(probability,seq(0,1,.1)));bin<-cut(probability,br,include.lowest=TRUE);data.table(bin=as.character(bin),probability,y)[,.(n=.N,predicted=mean(probability),observed=mean(y)),by=bin]},by=.(task,region)];wr(cal,path('results/models/calibration.tsv'))
logstage('models','PASS repeated nested CV, sensitivities and fixed-prediction bootstrap')
