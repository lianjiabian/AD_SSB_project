source('code/00_config.R')
input <- Sys.getenv('SSB_REVIEWED_CLINICAL_CSV',unset=path('INTERNAL_RESTRICTED/original_clinical/AD复核_多层级标签_最终人工复核版.csv'))
plan <- path('INTERNAL_RESTRICTED/original_clinical/Codex_SSB_Core1_最终分析与写作提示_v4_最终人工复核.md')
for(f in c(input,plan))stopifnot(file.copy(f,path('INTERNAL_RESTRICTED/original_clinical',basename(f)),overwrite=FALSE)||file.exists(path('INTERNAL_RESTRICTED/original_clinical',basename(f))))
x<-fread(input,na.strings=c('','NA'),check.names=FALSE);stopifnot(nrow(x)==171,uniqueN(x[['样本号']])==171)
final_list<-rd(path('INTERNAL_RESTRICTED/original_clinical/SSB_three_group_sample_list.tsv'))
stopifnot(nrow(final_list)==EXPECTED_N,uniqueN(final_list$sample_id)==EXPECTED_N,
          sum(final_list$group=='HC')==144L,sum(final_list$group=='AD')==89L,sum(final_list$group=='Other')==28L)
inputdir<-path('INTERNAL_RESTRICTED/analysis_inputs');dir.create(inputdir,recursive=TRUE,showWarnings=FALSE)
if(!file.exists(file.path(inputdir,'QC303_technical_linkage.tsv'))){old<-rd(file.path(PREVIOUS,'metadata/clinical_analysis_QC303.tsv'));wr(old[,.(sample_id,source_group,dedup_breakpoints,polya_retention)],file.path(inputdir,'QC303_technical_linkage.tsv'));wr(old[source_group=='HC'],file.path(inputdir,'HC_QC144_observed.tsv'));file.copy(file.path(PROJECT,'clinical_manual_review_20260927/biomarker_integrated_v2/metadata/Laboratory_dictionary.tsv'),file.path(inputdir,'Laboratory_dictionary.tsv'))}
old<-rd(file.path(inputdir,'QC303_technical_linkage.tsv'));labs<-rd(file.path(inputdir,'Laboratory_dictionary.tsv'))
h<-rd(file.path(inputdir,'HC_QC144_observed.tsv'));drop<-intersect(names(h),c('group3','group3_reviewed','clinical_probable_ad','grouping_basis','evidence_tier','grouping_status','grouping_review_required','group3_biomarker_sensitivity','group3_pet_only_sensitivity','diagnosis_only_group_reference'));h[,(drop):=NULL]
h[,`:=`(analysis_A=TRUE,analysis_B=TRUE,analysis_C=FALSE,hard_excluded=FALSE,ssb_qc_pass=TRUE,pathology_group='HC',core1_status='Not assessed in HC',exclusion_reason=NA_character_,diagnosis_original=NA_character_,diagnosis_reviewed=NA_character_,stage=NA_character_,clinical_phenotype='Healthy control',clinical_etiology=NA_character_,reviewed_severity=NA_character_,av45_status='Not assessed',csf_status='Not assessed',core1_evidence_source='Not assessed',review_note=NA_character_)]
d<-data.table(sample_id=trimws(x[['样本号']]),source_group='Disease-source',age_years=num(x[['年龄']]),sex=ifelse(x[['性别']]=='男','Male',ifelse(x[['性别']]=='女','Female',NA_character_)),mmse_observed_min=num(x[['同期MMSE']]),moca_unambiguous_score=num(x[['同期MoCA']]),adl_unambiguous_score=num(x[['同期ADL']]),age_at_onset_years=num(x[['起病年龄']]),diagnosis_original=x[['原诊断']],diagnosis_reviewed=x[['复核后分析诊断']],diagnosis_review_status=x[['诊断复核状态']],clinical_phenotype=x[['临床表型一级标签']],clinical_etiology=x[['临床病因/表型二级标签']],reviewed_severity=x[['复核后认知严重程度标签']],av45_status=x[['Core1_AV45状态']],csf_status=x[['Core1_CSF状态']],core1_status=x[['Core1综合状态']],core1_evidence_source=x[['Core1证据来源']],pathology_contribution=x[['AD病理贡献标签']],hard_excluded=x[['建议剔除样本（0保留1剔除）']]==1,exclusion_reason=x[['建议剔除原因']],analysis_A=x[['主分析A_宽泛疾病来源可用（1/0）']]==1,analysis_B=x[['主分析B_可用（1/0）']]==1,analysis_C=x[['探索分析C_可用（1/0）']]==1,stage=x[['探索分析C_AD连续谱阶段标签']],review_note=x[['数据复核提示']],age_eligibility_review=x[['纳入年龄判定']])
d[,pathology_group:=fcase(x[['主分析B_Core1病理比较分组']]=='Core1阳性_AD病理组',G3[2],x[['主分析B_Core1病理比较分组']]=='Core1阴性_认知障碍组',G3[3],x[['主分析B_Core1病理比较分组']]=='不进入主分析B_Core1未判定','Core 1 unavailable',default='Other eligible record')]
for(i in seq_len(nrow(labs))){v<-labs$variable[i];raw<-x[[labs$Disease_original_column[i]]];stopifnot(!is.null(raw));d[,(v):=num(raw)]}
for(p in list(c('hypertension','高血压'),c('diabetes','糖尿病'),c('smoking','吸烟'),c('alcohol_use','喝酒'),c('family_history','家族史'))){v<-num(x[[p[2]]]);v[!v%in%c(0,1)]<-NA;d[,(p[1]):=v]}
d[,`:=`(npi_unambiguous_score=num(x[['NPI-总分']]),hachinski_score=num(x[['Hachinski缺血']]),serum_abeta42_pg_ml=num(x[['血清Aβ42（pg/ml）']]),serum_tau181_pg_ml=num(x[['血清tau-181（pg/ml）']]),apoe_genotype=as.character(x[['APOE基因型']]))]
d[,ssb_qc_pass:=sample_id%in%old$sample_id]
for(v in c('dedup_breakpoints','polya_retention'))d[,(v):=old[[v]][match(sample_id,old$sample_id)]]
for(v in c('mmse_observed_min','moca_unambiguous_score'))d[get(v)<0 | get(v)>30,(v):=NA_real_]
unit_audit<-d[!is.na(hematocrit_pct)&hematocrit_pct>0&hematocrit_pct<1,.(sample_id,variable='hematocrit_pct',original_value=hematocrit_pct,analysis_value=hematocrit_pct*100,reason='Fraction recorded under percent-labelled field')]
d[!is.na(hematocrit_pct)&hematocrit_pct>0&hematocrit_pct<1,hematocrit_pct:=hematocrit_pct*100]
invalid<-list();for(v in labs$variable){ii<-which(!is.na(d[[v]])&(d[[v]]<0 | (grepl('_pct$',v)&d[[v]]>100)));if(length(ii)){invalid[[v]]<-data.table(sample_id=d$sample_id[ii],variable=v,original_value=d[[v]][ii],analysis_value=NA_real_,reason='Outside nonnegative or 0-100 percent domain');set(d,ii,v,NA_real_)}}
m<-rbindlist(list(h,d),fill=TRUE);m[,`:=`(sex_male=as.integer(sex=='Male'),case=as.integer(source_group=='Disease-source'),age10=age_years/10,log10_dedup_breakpoints=log10(dedup_breakpoints))]
m[,age_band:=fcase(is.na(age_years),NA_character_,age_years<50,'<50',age_years<60,'50-59',age_years<70,'60-69',default='70+')]
m[,`:=`(author_A_eligible=analysis_A,author_B_eligible=analysis_B,author_C_eligible=analysis_C)]
m[,`:=`(in_author_final_list=sample_id%in%final_list$sample_id,
        final_group=final_list$group[match(sample_id,final_list$sample_id)])]
m[,`:=`(included_A=analysis_A & ssb_qc_pass & !hard_excluded & in_author_final_list,
        included_B=analysis_B & ssb_qc_pass & !hard_excluded & in_author_final_list,
        included_C=analysis_C & ssb_qc_pass & !hard_excluded & in_author_final_list)]
m[,analysis_exclusion_reason:=fcase(hard_excluded,exclusion_reason,
        !ssb_qc_pass,'Not in SSB QC-approved manifest',
        !in_author_final_list,'Outside author-approved QC261 list; no inference of biomarker negativity',
        default=NA_character_)]
m[,complete_primary:=complete.cases(age_years,sex,log10_dedup_breakpoints,polya_retention)]
stopifnot(sum(m$included_A)==EXPECTED_N,sum(m$included_A&m$complete_primary)==259L,
 sum(m$included_B & m$source_group=='Disease-source')==117L,
 sum(m$included_B & m$pathology_group==G3[2])==89L,sum(m$included_B & m$pathology_group==G3[3])==28L,
 sum(!is.na(m[source_group=='Disease-source' & included_A,mmse_observed_min]))==100L,
 setequal(m[included_A==TRUE,sample_id],final_list$sample_id),all(m$included_A==m$included_B))
# Participant-specific adjudication checks are controlled inputs, not public code.
review_checks_file<-Sys.getenv('SSB_REVIEW_CHECKS_FILE',unset=path('INTERNAL_RESTRICTED/analysis_inputs/Participant_review_checks.tsv'))
stopifnot(file.exists(review_checks_file))
review_checks<-rd(review_checks_file);stopifnot(all(c('sample_id','variable','expected')%in%names(review_checks)))
for(k in seq_len(nrow(review_checks))){r<-review_checks[k];stopifnot(r$variable%in%names(m),sum(m$sample_id==r$sample_id)==1L);actual<-m[sample_id==r$sample_id][[r$variable]];stopifnot(identical(as.character(actual),as.character(r$expected)))}
wr(m,path('metadata/participant_manifest_all315.tsv'));wr(m[included_A==TRUE],path('metadata/clinical_analysis_A261.tsv'));wr(m[included_B==TRUE],path('metadata/clinical_analysis_B261.tsv'));saveRDS(m,path('metadata/participant_manifest.rds'))
wr(rbindlist(c(list(unit_audit),invalid),fill=TRUE),path('audit/clinical_unit_validity.tsv'))
wr(m[!is.na(review_note)&nzchar(review_note)],path('audit/current_review_notes.tsv'))
counts<-m[included_A==TRUE,.(n=.N,complete_covariates=sum(complete_primary),MMSE_observed=sum(!is.na(mmse_observed_min))),by=.(source_group,pathology_group)];wr(counts,path('metadata/analysis_counts.tsv'))
flow<-data.table(step=c('Patient-source clinical records','Manual exclusions','Retained clinical records','Author Main-B clinical eligibility','Main-B records absent from QC303','Included disease records from final author list','HC with SSB QC','Final author-list cohort'),n=c(171,13,158,121,4,117,144,EXPECTED_N));wr(flow,path('metadata/cohort_flow.tsv'))
savebook(list(Clinical_QC261=m[included_A==TRUE],All_records_audit=m,Analysis_counts=counts,Flow=flow),path('metadata/Clinical_final_manual_review_with_groups.xlsx'))
wr(m[included_A==FALSE],path('audit/excluded_outside_final_list.tsv'))
wr(m[included_A==TRUE,.(sample_id,group=final_group,pathology_group,source_group,age_years,sex,mmse_observed_min,complete_primary)],path('metadata/final_group_list.tsv'))
if(!file.exists(path('INTERNAL_RESTRICTED/original_clinical/AC.xlsx')))file.copy(file.path(PREVIOUS,'INTERNAL_RESTRICTED/original_clinical_workbooks/AC.xlsx'),path('INTERNAL_RESTRICTED/original_clinical/AC.xlsx'),overwrite=FALSE)
input_files<-c(input,plan,list.files(inputdir,full.names=TRUE));wr(data.table(file=input_files,md5=unname(tools::md5sum(input_files))),path('audit/clinical_input_checksums.tsv'))
logstage('clinical','PASS: final author list=261, complete=259; HC144 / AD89 / Other28; disease measured MMSE=100')
