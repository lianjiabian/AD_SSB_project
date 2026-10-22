source('code/00_config.R')
stopifnot(nzchar(Sys.getenv('SSB_DISCORDANT_SAMPLE_ID')))
suppressPackageStartupMessages({library(limma);library(openxlsx)})
stopifnot(rd(path('audit/metric_validation.tsv'))$status=='PASS')
m<-readRDS(path('metadata/analysis_metadata.rds'));m[,sex:=factor(sex,levels=c('Female','Male'))];m[,group:=factor(pathology_group,levels=G3)]
summary_rows<-list();allprimary<-list();ri<-rd(path('results/regional_Ri_fractions.tsv'))
fit_matrix<-function(Y,ann,d,formula,contrasts,label,space){
 d<-copy(d[complete.cases(d[,all.vars(formula),with=FALSE])]);X<-model.matrix(formula,d);stopifnot(qr(X)$rank==ncol(X),nrow(X)>ncol(X)+2)
 ff<-lmFit(Y[,d$sample_id,drop=FALSE],X);C<-matrix(0,nrow=ncol(X),ncol=length(contrasts),dimnames=list(colnames(X),names(contrasts)))
 for(j in seq_along(contrasts)){vv<-contrasts[[j]];stopifnot(all(names(vv)%in%rownames(C)));C[names(vv),j]<-vv}
 ff<-eBayes(contrasts.fit(ff,C),trend=TRUE,robust=TRUE)
 wr(d[,.(sample_id,source_group,pathology_group)],path('results/differential',paste0(space,'__',label,'__participants.tsv')))
 out<-list();for(j in seq_along(contrasts)){p<-ff$p.value[,j];se<-ff$stdev.unscaled[,j]*sqrt(ff$s2.post);cr<-qt(.975,ff$df.total)
  t<-data.table(gene_id=ann$gene_id,gene_name=ann$gene_name,gene_type=ann$gene_type,region_length_bp=ann$region_length_bp,region=space,model=label,contrast=names(contrasts)[j],n_model=nrow(d),beta=ff$coefficients[,j],SE=se,CI_low=ff$coefficients[,j]-cr*se,CI_high=ff$coefficients[,j]+cr*se,P=p,FDR=p.adjust(p,'BH'))
  wr(t,path('results/differential',paste0(space,'__',label,'__',names(contrasts)[j],'.tsv')))
  summary_rows[[length(summary_rows)+1L]]<<-t[,.(region=space,model=label,contrast=first(contrast),n_model=first(n_model),tested=.N,higher=sum(FDR<.05 & beta>0),lower=sum(FDR<.05 & beta<0),minimum_FDR=min(FDR))]
  out[[names(contrasts)[j]]]<-t
 };out
}
# Exact maximum-cardinality, minimum-age-distance rectangular assignment.
hungarian<-function(cost){n<-nrow(cost);mm<-ncol(cost);u<-numeric(n+1);v<-numeric(mm+1);p<-integer(mm+1);way<-integer(mm+1)
 for(i in seq_len(n)){p[1]<-i;j0<-1L;minv<-rep(Inf,mm+1);used<-rep(FALSE,mm+1)
  repeat{used[j0]<-TRUE;i0<-p[j0];delta<-Inf;j1<-0L
   for(j in 2:(mm+1))if(!used[j]){cur<-cost[i0,j-1]-u[i0+1]-v[j];if(cur<minv[j]){minv[j]<-cur;way[j]<-j0};if(minv[j]<delta){delta<-minv[j];j1<-j}}
   for(j in seq_len(mm+1)){if(used[j]){u[p[j]+1]<-u[p[j]+1]+delta;v[j]<-v[j]-delta}else minv[j]<-minv[j]-delta}
   j0<-j1;if(p[j0]==0)break
  }
  repeat{j1<-way[j0];p[j0]<-p[j1];j0<-j1;if(j0==1)break}
 };answer<-integer(n);for(j in 2:(mm+1))if(p[j]>0)answer[p[j]]<-j-1;answer
}
dn<-m[included_B==TRUE & pathology_group==G3[3] & complete_primary==TRUE][order(sample_id)];dp<-m[included_B==TRUE & pathology_group==G3[2] & complete_primary==TRUE][order(sample_id)]
dd<-abs(outer(dn$age_years,dp$age_years,'-'));valid<-outer(as.character(dn$sex),as.character(dp$sex),'==') & dd<=3
cost<-cbind(ifelse(valid,dd,1e6),matrix(1e4,nrow(dn),nrow(dn)));assignment<-hungarian(cost)
ok<-which(assignment<=nrow(dp));ok<-ok[valid[cbind(ok,assignment[ok])]];pairs<-rbindlist(lapply(seq_along(ok),function(k){j<-ok[k];z<-rbind(dn[j],dp[assignment[j]]);z[,matched_pair:=k];z}))
stopifnot(!anyDuplicated(pairs$sample_id));saveRDS(pairs,path('metadata/matched_pairs.rds'));wr(pairs,path('metadata/matched_pairs.tsv'))
wr(data.table(pairs=length(ok),participants=nrow(pairs),max_age_difference=if(length(ok))max(dd[cbind(ok,assignment[ok])])else NA,rule='Maximum cardinality; minimum summed age difference; same sex; <=3 years; no replacement'),path('results/sensitivity/matching_summary.tsv'))
for(s in SPACES){
 logstage('statistics',paste('Fitting',s));z<-readRDS(path('matrices',paste0(s,'_inputs.rds')));Y<-log2(z$lpkm+1);a<-z$annotation
 A<-fit_matrix(Y[a$eligible_A,,drop=FALSE],a[eligible_A==TRUE],m,~case+age_years+sex+log10_D+polya_retention,list(Disease_vs_HC=c(case=1)),'A_primary',s);allprimary[[s]]<-A[[1]]
 fit_matrix(Y[a$eligible_A,,drop=FALSE],a[eligible_A==TRUE],m,~case+age_years+sex,list(Disease_vs_HC=c(case=1)),'A_age_sex',s)
 db<-m[included_B==TRUE];db[,`:=`(is_pos=as.integer(pathology_group==G3[2]),is_neg=as.integer(pathology_group==G3[3]))]
 cc<-list(Positive_vs_HC=c(is_pos=1),Negative_vs_HC=c(is_neg=1),Positive_vs_Negative=c(is_pos=1,is_neg=-1))
 B<-fit_matrix(Y[a$eligible_B,,drop=FALSE],a[eligible_B==TRUE],db,~is_pos+is_neg+age_years+sex+log10_D+polya_retention,cc,'B_primary',s)
 cand<-merge(B[[1]][,.(gene_id,positive_beta=beta,positive_P=P,positive_FDR=FDR)],B[[2]][,.(gene_id,negative_beta=beta,negative_P=P,negative_FDR=FDR)],by='gene_id');cand<-merge(cand,B[[3]][,.(gene_id,direct_beta=beta,direct_P=P,direct_FDR=FDR)],by='gene_id');cand<-merge(a[,.(gene_id,gene_name)],cand,by='gene_id')
 cand[,`:=`(shared=positive_FDR<.05 & negative_FDR<.05 & sign(positive_beta)==sign(negative_beta),positive_only=positive_FDR<.05 & negative_FDR>=.05,negative_only=negative_FDR<.05 & positive_FDR>=.05,direct_associated=direct_FDR<.05)];wr(cand,path('results',paste0(s,'_shared_unique.tsv')))
 for(th in c(.1,.3)){keep<-a$detection_A>=th;fit_matrix(Y[keep,,drop=FALSE],a[keep],m,~case+age_years+sex+log10_D+polya_retention,list(Disease_vs_HC=c(case=1)),paste0('A_detection',th*100),s);keep<-a$detection_B>=th;fit_matrix(Y[keep,,drop=FALSE],a[keep],db,~is_pos+is_neg+age_years+sex+log10_D+polya_retention,cc,paste0('B_detection',th*100),s)}
 U<-log2(sweep(z$unshared_counts,2,z$D,'/')*1e10+1);ka<-rowMeans(z$unshared_counts>0)>=.2;kb<-rowMeans(z$unshared_counts[,m$included_B,drop=FALSE]>0)>=.2
 fit_matrix(U[ka,,drop=FALSE],a[ka],m,~case+age_years+sex+log10_D+polya_retention,list(Disease_vs_HC=c(case=1)),'A_unshared',s);fit_matrix(U[kb,,drop=FALSE],a[kb],db,~is_pos+is_neg+age_years+sex+log10_D+polya_retention,cc,'B_unshared',s)
 fit_matrix(Y[a$eligible_A,,drop=FALSE],a[eligible_A==TRUE],m,~case+age_years+sex+log10_D+polya_retention+wbc_10e9_l+neutrophil_pct+lymphocyte_pct,list(Disease_vs_HC=c(case=1)),'A_CBC',s)
 fit_matrix(Y[a$eligible_B,,drop=FALSE],a[eligible_B==TRUE],db,~is_pos+is_neg+age_years+sex+log10_D+polya_retention+wbc_10e9_l+neutrophil_pct+lymphocyte_pct,cc,'B_CBC',s)
 for(band in c('50-59','60-69','70+'))fit_matrix(Y[a$eligible_A,,drop=FALSE],a[eligible_A==TRUE],m[age_band==band],~case+age_years+sex+log10_D+polya_retention,list(Disease_vs_HC=c(case=1)),paste0('A_age_',gsub('[^0-9]','',band)),s)
 direct<-list(Positive_vs_Negative=c(is_pos=1))
 for(sub in c('exclude_discordant_record','AV45_only')){dd<-db[source_group=='Disease-source'];dd<-if(sub=='exclude_discordant_record')dd[sample_id!=Sys.getenv('SSB_DISCORDANT_SAMPLE_ID')] else dd[(pathology_group==G3[2]&av45_status=='阳性') | (pathology_group==G3[3]&av45_status=='阴性')];fit_matrix(Y[a$eligible_B,,drop=FALSE],a[eligible_B==TRUE],dd,~is_pos+age_years+sex+log10_D+polya_retention,direct,paste0('B_',sub),s)}
 if(nrow(pairs)>=20){dd<-copy(pairs);dd[,`:=`(matched_pair=factor(matched_pair),is_pos=as.integer(pathology_group==G3[2]))];fit_matrix(Y[a$eligible_B,,drop=FALSE],a[eligible_B==TRUE],dd,~matched_pair+is_pos+age_years+log10_D+polya_retention,direct,'B_matched',s)}
 ss<-data.table(sample_id=m$sample_id,region=s,mean_log_signal=colMeans(Y[a$eligible_A,,drop=FALSE]),median_log_signal=colMedians(Y[a$eligible_A,,drop=FALSE]),detected_fraction=colMeans(z$counts[a$eligible_A,,drop=FALSE]>0));wr(ss,path('results',paste0(s,'_sample_summaries.tsv')))
 rm(z,Y,U);gc()
}
wr(rbindlist(summary_rows),path('results/differential_summary.tsv'));joint<-rbindlist(allprimary);joint[,FDR_all_regions:=p.adjust(P,'BH')];wr(joint,path('results/primary_joint_FDR.tsv'))
top<-allprimary[[PRIMARY_SPACE]][order(FDR,-abs(beta),gene_id)][1:3];wr(top,path('results/representative_genes.tsv'))
wr(allprimary[['GENE']][order(FDR,-abs(beta),gene_id)][1:3],path('results/representative_GENE_sensitivity.tsv'))
effects<-tests<-list()
for(s in SPACES){
 d<-merge(m,ri[region==s],by='sample_id');d[,V:=log2(Ri+1)]
 for(label in c('age_sex','technical')){f<-if(label=='age_sex')V~case+age_years+sex else V~case+age_years+sex+log10_D+polya_retention;ff<-lm(f,d);k<-'case';ci<-confint(ff,k);cf<-coef(summary(ff));effects[[paste(s,label)]]<-data.table(region=s,model=label,contrast='Disease_vs_HC',n=nobs(ff),beta=cf[k,1],CI_low=ci[1],CI_high=ci[2],ratio=2^cf[k,1],ratio_low=2^ci[1],ratio_high=2^ci[2],P=cf[k,4])}
 tt<-wilcox.test(Ri~source_group,d,exact=FALSE);tests[[s]]<-data.table(region=s,test='Two-sided Wilcoxon',n=nrow(d),P=tt$p.value,HC_n=sum(d$source_group=='HC'),Disease_n=sum(d$source_group=='Disease-source'))
 db<-d[included_B==TRUE];db[,group:=factor(pathology_group,levels=G3)];X<-model.matrix(~group+age_years+sex+log10_D+polya_retention,db[complete_primary==TRUE]);xx<-db[complete_primary==TRUE]
 # Dedicated three-group regional contrasts via limma provide common covariance.
 fit<-eBayes(lmFit(matrix(xx$V,nrow=1),X));C<-matrix(0,nrow=ncol(X),ncol=3,dimnames=list(colnames(X),c('Positive_vs_HC','Negative_vs_HC','Positive_vs_Negative')));C[2,]<-c(1,0,1);C[3,]<-c(0,1,-1);cf<-eBayes(contrasts.fit(fit,C))
 for(k in 1:3){se<-cf$stdev.unscaled[,k]*sqrt(cf$s2.post);cr<-qt(.975,cf$df.total);effects[[paste(s,k)]]<-data.table(region=s,model='B_technical',contrast=colnames(C)[k],n=nrow(xx),beta=cf$coefficients[,k],CI_low=cf$coefficients[,k]-cr*se,CI_high=cf$coefficients[,k]+cr*se,P=cf$p.value[,k])}
}
ee<-rbindlist(effects,fill=TRUE);ee[,FDR:=p.adjust(P,'BH'),by=model];wr(ee,path('results/regional_models.tsv'));tt<-rbindlist(tests);tt[,FDR:=p.adjust(P,'BH')];wr(tt,path('results/regional_descriptive_tests.tsv'))
pairtests<-list();pairs3<-list(Positive_vs_HC=c(G3[2],G3[1]),Negative_vs_HC=c(G3[3],G3[1]),Positive_vs_Negative=c(G3[2],G3[3]))
for(s in SPACES){d<-merge(m,ri[region==s],by='sample_id');for(ct in names(pairs3)){g<-pairs3[[ct]];dd<-d[pathology_group%in%g];wt<-wilcox.test(Ri~pathology_group,dd,exact=FALSE);pairtests[[paste(s,ct)]]<-data.table(region=s,contrast=ct,n=nrow(dd),group1=g[1],group2=g[2],n1=sum(dd$pathology_group==g[1]),n2=sum(dd$pathology_group==g[2]),P=wt$p.value,test='Two-sided unpaired Wilcoxon; descriptive')}}
pt<-rbindlist(pairtests);pt[,FDR:=p.adjust(P,'BH')];wr(pt,path('results/regional_three_group_descriptive_tests.tsv'))
age<-list();for(s in SPACES){d<-merge(m,rd(path('results',paste0(s,'_sample_summaries.tsv'))),by='sample_id');for(metric in c('mean_log_signal','median_log_signal','detected_fraction')){fit<-lm(as.formula(paste(metric,'~age10+case+sex+log10_D+polya_retention')),d);cf<-coef(summary(fit));ci<-confint(fit,'age10');age[[paste(s,metric)]]<-data.table(region=s,metric=metric,n=nobs(fit),beta=cf['age10',1],CI_low=ci[1],CI_high=ci[2],P=cf['age10',4]);fi<-lm(as.formula(paste(metric,'~age10*case+sex+log10_D+polya_retention')),d);cf<-coef(summary(fi));ci<-confint(fi,'age10:case');age[[paste(s,metric,'interaction')]]<-data.table(region=s,metric=paste0(metric,'_interaction'),n=nobs(fi),beta=cf['age10:case',1],CI_low=ci[1],CI_high=ci[2],P=cf['age10:case',4])}}
aa<-rbindlist(age);aa[,FDR:=p.adjust(P,'BH'),by=metric];wr(aa,path('results/age_models.tsv'))
logstage('statistics','PASS differential, Ri, matching and age analyses complete')
