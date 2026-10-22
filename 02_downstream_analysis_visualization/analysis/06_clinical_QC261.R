source('code/00_config.R');suppressPackageStartupMessages({library(limma);library(openxlsx)})
m<-readRDS(path('metadata/analysis_metadata.rds'));m[,sex:=factor(sex,levels=c('Female','Male'))]
vars<-c('age_years','sex_male','mmse_observed_min','moca_unambiguous_score','adl_unambiguous_score','wbc_10e9_l','neutrophil_pct','lymphocyte_pct','monocyte_pct','rbc_10e12_l','hemoglobin_g_l','hematocrit_pct','mcv_fl','platelet_10e9_l','glucose_mmol_l','creatinine_umol_l','cholesterol_mmol_l','triglycerides_mmol_l','hdl_c_mmol_l','ldl_c_mmol_l','D','polya_retention')
summ<-function(d,v){x<-d[[v]];n<-sum(!is.na(x));if(!n)return(sprintf('NA; missing %d',nrow(d)));if(v=='sex_male')return(sprintf('%d/%d (%.1f%%); missing %d',sum(x==1,na.rm=TRUE),n,100*mean(x==1,na.rm=TRUE),nrow(d)-n));sprintf('%.2f [%.2f, %.2f]; missing %d',median(x,na.rm=TRUE),quantile(x,.25,na.rm=TRUE),quantile(x,.75,na.rm=TRUE),nrow(d)-n)}
ptest<-function(d,v,grp){dd<-d[!is.na(get(v))];if(uniqueN(dd[[grp]])<2)return(NA_real_);if(v=='sex_male')return(fisher.test(table(dd[[grp]],dd[[v]]))$p.value);if(uniqueN(dd[[v]])<2)return(1);wilcox.test(as.formula(paste(v,'~',grp)),dd,exact=FALSE)$p.value}
tab<-rbindlist(lapply(vars,function(v){dp<-m[source_group=='Disease-source'];data.table(variable=v,All=summ(m,v),HC=summ(m[source_group=='HC'],v),Combined_disease=summ(dp,v),P_combined=ptest(m,v,'source_group'),AD=summ(dp[pathology_group==G3[2]],v),Other=summ(dp[pathology_group==G3[3]],v),P_AD_Other=ptest(dp,v,'pathology_group'))}))
for(pair in list(c('AV45 positive record','av45_status','阳性'),c('AV45 negative record','av45_status','阴性'),c('CSF Core 1-positive record','csf_status','阳性'))){
 v<-pair[2];wanted<-pair[3];obs<-function(d){if(all(d$source_group=='HC'))return('Not assessed');x<-as.character(d[[v]]);available<-x%in%c('阳性','阴性');sprintf('%d/%d; unavailable %d',sum(x==wanted,na.rm=TRUE),sum(available),sum(!available))}
 tab<-rbind(tab,data.table(variable=pair[1],All='See group-specific evidence',HC='Not assessed',Combined_disease=obs(m[source_group=='Disease-source']),P_combined=NA_real_,AD=obs(m[pathology_group==G3[2]]),Other=obs(m[pathology_group==G3[3]]),P_AD_Other=NA_real_))
}
wr(tab,path('tables/Table1.tsv'));savebook(list(Table1=tab),path('tables/Table1.xlsx'))
miss<-rbindlist(lapply(setdiff(names(m)[vapply(m,is.numeric,logical(1))],c('case','age10','log10_D','log10_dedup_breakpoints')),function(v)m[,.(variable=v,n=.N,observed=sum(!is.na(get(v))),missing=sum(is.na(get(v)))),by=pathology_group]));wr(miss,path('tables/clinical_missingness.tsv'))
wr(m[,.(n=.N),by=.(source_group,pathology_group,av45_status,csf_status,core1_status)],path('tables/Core1_evidence_counts.tsv'))
labs<-rd(path('INTERNAL_RESTRICTED/analysis_inputs/Laboratory_dictionary.tsv'))$variable
traits<-intersect(unique(c('mmse_observed_min','moca_unambiguous_score','adl_unambiguous_score','age_at_onset_years','serum_abeta42_pg_ml','serum_tau181_pg_ml',labs)),names(m))
participant_dir<-path('results/clinical/participants');dir.create(participant_dir,recursive=TRUE,showWarnings=FALSE)
slug<-function(v)gsub('[^A-Za-z0-9]','_',v)
pop_subset<-function(d,pop){if(pop=='Disease-source')d[source_group=='Disease-source']else if(pop=='All')d else d[pathology_group==pop]}
assoc<-function(d,trait,outcome,pop){
 dd<-d[complete.cases(get(outcome),get(trait),age_years,sex,log10_D,polya_retention)]
 if(nrow(dd)<20||uniqueN(dd[[trait]])<3||uniqueN(dd[[outcome]])<3)return(NULL)
 co<-cor.test(dd[[outcome]],dd[[trait]],method='spearman',exact=FALSE)
 dd[,trait_z:=(get(trait)-mean(get(trait)))/sd(get(trait))]
 covs<-c('age_years','sex','log10_D','polya_retention');covs<-covs[vapply(covs,function(v)uniqueN(dd[[v]])>1,logical(1))]
 if(pop=='All'&&uniqueN(dd$case)>1)covs<-c(covs,'case')
 if(pop=='Disease-source'&&uniqueN(dd$pathology_group)>1)covs<-c(covs,'factor(pathology_group)')
 f<-as.formula(paste(outcome,'~trait_z',if(length(covs))paste('+',paste(covs,collapse='+'))else''));ff<-lm(f,dd);cf<-coef(summary(ff));ci<-confint(ff,'trait_z')
 if(!'trait_z'%in%rownames(cf))return(NULL)
 list(stat=data.table(n=nrow(dd),rho=unname(co$estimate),P=co$p.value,beta=cf['trait_z',1],CI_low=ci[1],CI_high=ci[2],adjusted_P=cf['trait_z',4],covariates=paste(covs,collapse=';')),participants=dd[,.(sample_id)])
}
scores<-rd(path('results/models/participant_mean_OOF.tsv'))[task%in%c('source','pathology')&region%in%SPACES]
d<-merge(scores,m,by='sample_id');out<-list()
for(tt in c('source','pathology'))for(pop in if(tt=='source')c('All','Disease-source',G3[2],G3[3])else c('Disease-source',G3[2],G3[3]))for(s in SPACES)for(v in traits){
 dd<-pop_subset(d[task==tt & region==s],pop);a<-assoc(dd,v,'probability',pop);if(is.null(a))next
 out[[length(out)+1L]]<-cbind(data.table(task=tt,population=pop,region=s,trait=v),a$stat)
 wr(a$participants,file.path(participant_dir,paste0(tt,'_',slug(pop),'_',s,'_',v,'.tsv')))
}
cc<-rbindlist(out);cc[,`:=`(FDR=p.adjust(P,'BH'),adjusted_FDR=p.adjust(adjusted_P,'BH')),by=.(task,population)];wr(cc,path('results/clinical/model_trait_associations.tsv'))
mm<-list();for(tt in c('source','pathology'))for(s in SPACES){
 dd<-d[task==tt&region==s&source_group=='Disease-source'&!is.na(mmse_observed_min)]
 ff<-lm(mmse_observed_min~probability+age_years+sex+log10_D+polya_retention,dd);cf<-coef(summary(ff));ci<-confint(ff,'probability')
 mm[[paste(tt,s)]]<-data.table(task=tt,region=s,n=nobs(ff),beta=cf['probability',1],CI_low=ci[1],CI_high=ci[2],P=cf['probability',4])
};mm<-rbindlist(mm);mm[,FDR:=p.adjust(P,'BH'),by=task];wr(mm,path('results/clinical/MMSE_outcome_models.tsv'))

# Direct regional signal / Ri associations, independent of classifier scores.
out<-list();for(s in SPACES){ss<-merge(m,rd(path('results',paste0(s,'_sample_summaries.tsv'))),by='sample_id');rr<-rd(path('results/regional_Ri_fractions.tsv'))[region==s,.(sample_id,Ri)];ss<-merge(ss,rr,by='sample_id')
 for(metric in c('mean_log_signal','Ri'))for(pop in c('All','Disease-source',G3[2],G3[3]))for(v in traits){a<-assoc(pop_subset(ss,pop),v,metric,pop);if(is.null(a))next;out[[length(out)+1L]]<-cbind(data.table(population=pop,region=s,metric=metric,trait=v),a$stat);wr(a$participants,file.path(participant_dir,paste0('signal_',slug(pop),'_',s,'_',metric,'_',v,'.tsv')))}
};a<-rbindlist(out);a[,`:=`(FDR=p.adjust(P,'BH'),adjusted_FDR=p.adjust(adjusted_P,'BH')),by=.(population,metric)];wr(a,path('results/clinical/regional_signal_trait_associations.tsv'))

top<-rd(path('results/representative_genes.tsv'));z<-readRDS(path('matrices',paste0(PRIMARY_SPACE,'_inputs.rds')));Y<-log2(z$lpkm[match(top$gene_id,z$annotation$gene_id),m$sample_id,drop=FALSE]+1)
gdata<-rbindlist(lapply(seq_len(nrow(top)),function(j){dd<-copy(m);dd[,`:=`(gene_id=top$gene_id[j],gene_name=top$gene_name[j],signal=Y[j,match(sample_id,m$sample_id)])];dd}))
out<-list();for(g in top$gene_id)for(pop in c('All','Disease-source',G3[2],G3[3]))for(v in traits){dd<-pop_subset(gdata[gene_id==g],pop);a<-assoc(dd,v,'signal',pop);if(is.null(a))next;out[[length(out)+1L]]<-cbind(data.table(population=pop,region=PRIMARY_SPACE,gene_id=g,gene_name=top[gene_id==g,gene_name],trait=v),a$stat);wr(a$participants,file.path(participant_dir,paste0('representative_',slug(pop),'_',g,'_',v,'.tsv')))}
a<-rbindlist(out);a[,`:=`(FDR=p.adjust(P,'BH'),adjusted_FDR=p.adjust(adjusted_P,'BH')),by=population];wr(a,path('results/clinical/representative_feature_trait_associations.tsv'));wr(gdata[,.(sample_id,gene_id,gene_name,signal)],path('results/clinical/representative_feature_values.tsv'))

stage_counts<-m[included_C==TRUE,.N,by=stage];wr(stage_counts,path('results/stage/stage_counts.tsv'))
early<-'Core1+_AD早期/轻度';moderate<-'Core1+_AD中度及以上';ds<-m[included_C==TRUE & stage%in%c(early,moderate) & complete_primary==TRUE];ds[,moderate_stage:=as.integer(stage==moderate)]
stage_results<-list();for(s in SPACES){rr<-rd(path('results/regional_Ri_fractions.tsv'))[region==s];dd<-merge(ds,rr,by='sample_id');dd[,V:=log2(Ri+1)];ff<-lm(V~moderate_stage+age_years+sex+log10_D+polya_retention,dd);cf<-coef(summary(ff));ci<-confint(ff,'moderate_stage');stage_results[[s]]<-data.table(region=s,metric='log2(Ri+1)',n=nobs(ff),beta=cf['moderate_stage',1],CI_low=ci[1],CI_high=ci[2],P=cf['moderate_stage',4])}
st<-rbindlist(stage_results);st[,FDR:=p.adjust(P,'BH')];wr(st,path('results/stage/early_vs_moderate_Ri.tsv'))
YY<-Y[,match(ds$sample_id,m$sample_id),drop=FALSE];X<-model.matrix(~moderate_stage+age_years+sex+log10_D+polya_retention,ds);fit<-eBayes(lmFit(YY,X),trend=TRUE,robust=TRUE);k<-match('moderate_stage',colnames(X));se<-fit$stdev.unscaled[,k]*sqrt(fit$s2.post);cr<-qt(.975,fit$df.total)
wr(data.table(region=PRIMARY_SPACE,gene_id=top$gene_id,gene_name=top$gene_name,n=nrow(ds),beta=fit$coefficients[,k],CI_low=fit$coefficients[,k]-cr*se,CI_high=fit$coefficients[,k]+cr*se,P=fit$p.value[,k],FDR=p.adjust(fit$p.value[,k],'BH')),path('results/stage/representative_genes_stage.tsv'))
stage_more<-list();for(v in c('mmse_observed_min','moca_unambiguous_score')){dd<-ds[!is.na(get(v))];ff<-lm(as.formula(paste(v,'~moderate_stage+age_years+sex+log10_D+polya_retention')),dd);cf<-coef(summary(ff));ci<-confint(ff,'moderate_stage');stage_more[[v]]<-data.table(outcome=v,n=nobs(ff),beta=cf['moderate_stage',1],CI_low=ci[1],CI_high=ci[2],P=cf['moderate_stage',4])}
for(tt in c('source','pathology'))for(s in SPACES){dd<-merge(ds,scores[task==tt&region==s],by='sample_id');ff<-lm(probability~moderate_stage+age_years+sex+log10_D+polya_retention,dd);cf<-coef(summary(ff));ci<-confint(ff,'moderate_stage');stage_more[[paste(tt,s)]]<-data.table(outcome=paste(tt,s,'OOF_score'),n=nobs(ff),beta=cf['moderate_stage',1],CI_low=ci[1],CI_high=ci[2],P=cf['moderate_stage',4])};st<-rbindlist(stage_more);st[,FDR:=p.adjust(P,'BH')];wr(st,path('results/stage/early_vs_moderate_clinical_scores.tsv'))
logstage('clinical','PASS observed Table1; source/pathology scores, direct regional signals, primary EXON features and actual-n clinical/stage associations')
