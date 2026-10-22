source('code/00_config.R')
suppressPackageStartupMessages(library(openxlsx))
for(d in c('excel/panels','excel/figures','excel/master_tables'))dir.create(path(d),recursive=TRUE,showWarnings=FALSE)
required<-c('Fig1H','FigS14E','Fig2I','Fig3E','Fig3F','Fig4G','Fig4H')
stopifnot(all(required%in%names(readRDS(path('audit/figure_registry.rds'))$captions)))
registry<-readRDS(path('audit/figure_registry.rds'));m<-readRDS(path('metadata/analysis_metadata.rds'))
clean_excel<-function(x){
 x<-as.data.frame(x);omitted<-character()
 for(n in names(x)){
   if(is.list(x[[n]]))x[[n]]<-vapply(x[[n]],paste,character(1),collapse='; ')
   if(is.character(x[[n]])&&any(nchar(x[[n]],type='chars',allowNA=TRUE)>32760,na.rm=TRUE))omitted<-c(omitted,n)
 }
 if(length(omitted))x[omitted]<-NULL
 attr(x,'omitted_columns')<-omitted;x
}
newbook<-function(){w<-createWorkbook();modifyBaseFont(w,fontName='Arial',fontSize=10);w}
put<-function(w,name,x){
 name<-substr(gsub('[^A-Za-z0-9_]','_',name),1,31);x<-clean_excel(x)
 if(nrow(x)>1048575||ncol(x)>16384)stop('Excel dimensions exceeded: ',name)
 addWorksheet(w,name);writeData(w,name,x,withFilter=nrow(x)>0&&ncol(x)>0,keepNA=TRUE,na.string='NA')
 if(ncol(x)){addStyle(w,name,createStyle(fgFill='#3C5488',fontColour='white',textDecoration='bold'),rows=1,cols=seq_len(ncol(x)),gridExpand=TRUE);setColWidths(w,name,seq_len(ncol(x)),widths=21);freezePane(w,name,firstRow=TRUE,firstCol=TRUE)}
 invisible(attr(x,'omitted_columns'))
}
ids<-names(registry$captions)
changed<-Sys.getenv('SSB_EXPORT_CHANGED',unset='');export_ids<-if(nzchar(changed))intersect(ids,strsplit(changed,',',fixed=TRUE)[[1]])else ids
all_membership<-rbindlist(lapply(names(registry$main),function(n)data.table(panel=registry$main[[n]],figure=n,role='Main')),fill=TRUE)
all_membership<-rbindlist(list(all_membership,rbindlist(lapply(names(registry$supplementary_layout),function(n)data.table(panel=registry$supplementary_layout[[n]],figure=paste0('Figure_',n),role='Supplementary')))),fill=TRUE)
roleof<-function(id){z<-all_membership[panel==id];if(nrow(z))paste(z$figure,collapse='; ')else 'Additional standalone'}
export_panel<-function(id){
 file<-path('excel/panels',paste0(id,'_source_data.xlsx'))
 d<-rd(path('source_data',id,'plot_data.tsv'));st<-rd(path('source_data',id,'statistics.tsv'));pa<-rd(path('source_data',id,'participants.tsv'))
 w<-newbook();put(w,'Plot_data',d);put(w,'Statistics',st);put(w,'Participants',pa)
 omitted<-unique(c(attr(clean_excel(d),'omitted_columns'),attr(clean_excel(st),'omitted_columns')))
 guide<-data.table(item=c('Panel','Location','Participant n','Plot rows','Statistics rows','Missing values','Nominal versus adjusted P','Units and biological unit','R entry point','Legend English','Legend Chinese','Long text columns'),
 value=c(id,roleof(id),as.character(uniqueN(pa$sample_id)),as.character(nrow(d)),as.character(nrow(st)),
 'NA means unavailable; zero is retained only when actually observed/computed',
 'Plots display nominal P; FDR/adjusted_P fields preserve the complete predefined multiplicity families',
 'See the panel legend and field names. Participant is the clinical unit; genes/bins/fits are not independent patients',
 paste0('code/panels/',id,'.R'),registry$captions[[id]]$en,registry$captions[[id]]$zh,
 if(length(omitted))paste0('Excel cell-length limit: these columns remain complete in TSV: ',paste(omitted,collapse=', '))else 'No column omitted'))
 put(w,'Guide',guide);saveWorkbook(w,file,overwrite=TRUE)
 # Actual identity round trip is checked for every panel, including empty
 # annotation-only participant manifests.
 if(nrow(pa)){back<-read.xlsx(file,sheet='Participants',check.names=FALSE);stopifnot(identical(as.character(back$sample_id),as.character(pa$sample_id)))}
 data.table(panel=id,plot_rows=nrow(d),statistics_rows=nrow(st),participant_rows=nrow(pa),unique_participants=uniqueN(pa$sample_id),excel=file,status='PASS')
}
cat(format(Sys.time()),'Exporting',length(ids),'panel workbooks\n');flush.console()
validation<-parallel::mclapply(export_ids,export_panel,mc.cores=3L,mc.preschedule=FALSE)
if(any(vapply(validation,inherits,logical(1),'try-error')))stop('Panel Excel export failed')
validation<-rbindlist(validation);if(nzchar(changed)&&file.exists(path('audit/Excel_panel_roundtrip.tsv')))validation<-rbindlist(list(rd(path('audit/Excel_panel_roundtrip.tsv'))[panel%in%ids&!panel%in%export_ids],validation),fill=TRUE);wr(validation,path('audit/Excel_panel_roundtrip.tsv'))

layouts<-c(registry$main,setNames(registry$supplementary_layout,paste0('Figure_',names(registry$supplementary_layout))))
for(n in names(layouts)){
 existing<-path('excel/figures',paste0(n,'_source_data.xlsx'))
 if(nzchar(changed)&&!any(layouts[[n]]%in%export_ids)&&file.exists(existing)&&identical(as.character(read.xlsx(existing,sheet='Panel_index')$panel),as.character(layouts[[n]])))next
 w<-newbook();pids<-layouts[[n]];guide<-data.table(panel=pids,legend=vapply(pids,function(id)registry$captions[[id]]$en,character(1)),source_workbook=paste0('../panels/',pids,'_source_data.xlsx'))
 put(w,'Panel_index',guide)
 for(id in pids){put(w,paste0(id,'_data'),rd(path('source_data',id,'plot_data.tsv')));put(w,paste0(id,'_stats'),rd(path('source_data',id,'statistics.tsv')));put(w,paste0(id,'_patients'),rd(path('source_data',id,'participants.tsv')))}
 saveWorkbook(w,path('excel/figures',paste0(n,'_source_data.xlsx')),overwrite=TRUE)
 cat(format(Sys.time()),'Figure Excel',n,'\n');flush.console()
}

# Final authority: current manual labels, not the historical clinical AD split.
group_columns<-c('sample_id','final_group','source_group','pathology_group','core1_status','core1_evidence_source','av45_status','csf_status','diagnosis_original','diagnosis_reviewed','diagnosis_review_status','clinical_phenotype','clinical_etiology','reviewed_severity','stage','age_years','sex','mmse_observed_min','moca_unambiguous_score','adl_unambiguous_score','analysis_A','analysis_B','analysis_C','included_A','included_B','included_C','complete_primary','D','polya_retention')
g<-copy(m[,intersect(group_columns,names(m)),with=FALSE]);g[,`:=`(MMSE_concurrent_score=mmse_observed_min,B_direct_pathology_included=included_B&source_group=='Disease-source',A_model_included=included_A&complete_primary,B_model_included=included_B&complete_primary)]
counts<-g[,.(participants=.N,A_complete=sum(A_model_included),B_complete=sum(B_model_included),MMSE_observed=sum(!is.na(MMSE_concurrent_score))),by=.(source_group,pathology_group)]
dict<-data.table(field=c('sample_id','source_group','pathology_group','included_A','included_B','B_direct_pathology_included','included_C','complete_primary','diagnosis_original','diagnosis_reviewed','mmse_observed_min','MMSE_concurrent_score'),definition=c('SSB sequencing sample ID; unique participant key','HC versus combined author-selected AD and Other; no Core 1 unavailable participants are added','AD = author-reviewed Core 1 positive; Other = Core 1-negative cognitive disorder; HC is not assumed biomarker-negative','Final author-list cohort: 261 participants','Three-group pathology population with HC: 261 participants','Direct AD versus Other comparison: 117 participants','Reviewed Core 1-positive clinical-stage population: 89 participants','Complete age/sex/technical covariates: 259 (HC142, AD89, Other28)','Original diagnosis text, preserved rather than used alone to override Core 1 labels','Current manually reviewed clinical analysis diagnosis','Legacy field name: current contemporaneous numeric score, not a historical minimum','Descriptive alias of the current contemporaneous numeric score'))
savebook(list(Final_QC261=g,B_direct117=g[B_direct_pathology_included==TRUE],C_stages89=g[included_C==TRUE],Grouping_counts=counts,Grouping_definitions=dict),path('excel/master_tables/Final_analysis_grouping.xlsx'))
labvars<-rd(path('INTERNAL_RESTRICTED/analysis_inputs/Laboratory_dictionary.tsv'))$variable
clinical_fields<-intersect(unique(c(group_columns,labvars,'age_at_onset_years','hypertension','diabetes','smoking','alcohol_use','family_history','npi_unambiguous_score','hachinski_score','serum_abeta42_pg_ml','serum_tau181_pg_ml','apoe_genotype','author_A_eligible','author_B_eligible','author_C_eligible')),names(m))
clinical_final<-m[,..clinical_fields]
savebook(list(Clinical_final_QC261=clinical_final,Grouping_definitions=dict,Grouping_counts=counts,Missingness=rd(path('tables/clinical_missingness.tsv'))),path('excel/master_tables/Clinical_final_observed.xlsx'))
savebook(list(Table1=rd(path('tables/Table1.tsv'))),path('excel/master_tables/Table1.xlsx'))
savebook(list(Regional_Ri=rd(path('results/regional_Ri_fractions.tsv')),Library_D=rd(path('metadata/library_denominators.tsv')),Chromosome_counts=rd(path('metadata/library_counts_by_chromosome.tsv')),Ri_reference=rd(path('audit/metric_validation.tsv'))),path('excel/master_tables/SSB_Ri_and_library_denominators.xlsx'))

# Full primary and pathology result tables, not just significant subsets.
if(!nzchar(changed)){
w<-newbook();put(w,'Analysis_summary',rd(path('results/differential_summary.tsv')))
for(s in SPACES)for(ct in c('Disease_vs_HC','Positive_vs_HC','Negative_vs_HC','Positive_vs_Negative')){
 model<-if(ct=='Disease_vs_HC')'A_primary'else'B_primary';short<-c(Disease_vs_HC='Source_HC',Positive_vs_HC='Positive_HC',Negative_vs_HC='Negative_HC',Positive_vs_Negative='Positive_Negative')[[ct]]
 put(w,paste0(s,'_',short),rd(path('results/differential',paste0(s,'__',model,'__',ct,'.tsv'))))
}
extra<-c(Ri_tests='results/regional_descriptive_tests.tsv',Ri_models='results/regional_models.tsv',Age_models='results/age_models.tsv',Profile_tests='results/profile/adjusted_tests.tsv',Model_performance='results/models/performance.tsv',Repeated_AUC='results/models/repeated_metrics.tsv',Clinical_associations='results/clinical/model_trait_associations.tsv',MMSE_models='results/clinical/MMSE_outcome_models.tsv',Stage_Ri='results/stage/early_vs_moderate_Ri.tsv',Stage_genes='results/stage/representative_genes_stage.tsv',Enrichment='results/enrichment/all_terms.tsv',Length_sensitivity='results/enrichment/length_stratified_sensitivity.tsv',Direction_robustness='results/sensitivity/broad_direction_concordance.tsv',GENE_sets='results/GENE_shared_unique.tsv')
for(n in names(extra))put(w,n,rd(path(extra[[n]])))
saveWorkbook(w,path('excel/master_tables/Analysis_statistics_complete.xlsx'),overwrite=TRUE);rm(w);gc()
}

inventory<-data.table(file=list.files(ROOT,recursive=TRUE,full.names=TRUE))
inventory<-inventory[!grepl('/INTERNAL_RESTRICTED/|/checkpoints/|/logs/|/figures/|/excel/',file)]
inventory[,`:=`(relative_file=substring(file,nchar(ROOT)+2),bytes=file.info(file)$size,md5=unname(tools::md5sum(file)))];inventory[,file:=NULL]
matrix_catalog<-rbindlist(lapply(SPACES,function(s)data.table(region=s,raw_count_tsv=paste0('matrices/SSB_counts_',tolower(s),'.tsv'),LPKM_tsv=paste0('matrices/SSB_LPKM_',tolower(s),'.tsv'),input_rds=paste0('matrices/',s,'_inputs.rds'),excel=paste0('excel/raw_matrices/SSB_',s,'_counts_and_LPKM.xlsx'),orientation='Gene rows x sample columns',normalization='Count * 1e10 / complete-library D')))
data_index<-merge(rd(path('metadata/library_denominators.tsv')),g[,.(sample_id,source_group,pathology_group,age_years,sex,included_A,included_B,B_direct_pathology_included,A_model_included)],by='sample_id')
statistics_index<-data.table(file=list.files(path('results'),pattern='[.]tsv$',recursive=TRUE,full.names=TRUE));statistics_index[,relative_file:=substring(file,nchar(ROOT)+2)];statistics_index[,bytes:=file.info(file)$size];statistics_index[,file:=NULL]
savebook(list(Sample_data_index=data_index,Matrix_catalog=matrix_catalog,File_inventory=inventory,Statistics_index=statistics_index,Figure_panel_index=all_membership),path('excel/master_tables/Data_and_statistics_index.xlsx'))
wr(data.table(file=list.files(path('excel'),pattern='[.]xlsx$',recursive=TRUE,full.names=TRUE)),path('audit/Excel_inventory.tsv'))
logstage('source_excel','PASS panel/figure workbooks, final grouping, observed clinical, raw data and complete main/pathology statistics')
