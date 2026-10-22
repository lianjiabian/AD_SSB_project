source('R/00_common.R')
AUTHOR_MS<-Sys.getenv('SSB_AUTHOR_MANUSCRIPT',unset=P('author_inputs/Manuscript_author_revised_EN.md'))
AUTHOR_PLAN<-Sys.getenv('SSB_AUTHOR_PLAN',unset=P('author_inputs/Author_reorganization_requirements.md'))
stopifnot(file.exists(AUTHOR_MS),file.exists(AUTHOR_PLAN))
if(normalizePath(AUTHOR_MS)!=normalizePath(P('author_inputs/Manuscript_author_revised_EN.md'),mustWork=FALSE))file.copy(AUTHOR_MS,P('author_inputs/Manuscript_author_revised_EN.md'),overwrite=TRUE)
if(normalizePath(AUTHOR_PLAN)!=normalizePath(P('author_inputs/Author_reorganization_requirements.md'),mustWork=FALSE))file.copy(AUTHOR_PLAN,P('author_inputs/Author_reorganization_requirements.md'),overwrite=TRUE)
origreg<-readRDS(file.path(BASE,'audit/figure_registry.rds'))
baseline_files<-c('audit/figure_registry.rds','metadata/analysis_metadata.rds','results/differential_summary.tsv','tables/Table1.tsv','FINAL_SUBMISSION_PACKAGE/Tables/Table1.docx','FINAL_SUBMISSION_PACKAGE/Tables/Table1.xlsx','FINAL_SUBMISSION_PACKAGE/Tables/Supplementary_Data_1.xlsx')
wr(data.table(file=baseline_files,md5=unname(tools::md5sum(file.path(BASE,baseline_files)))),P('mapping_and_QC/baseline_checksums.tsv'))
# Preserve old panels and source tables without executing any statistical script.
copy_tree(file.path(BASE,'figures/panels'),P('source_panels/originals'))
copy_tree(file.path(BASE,'source_data'),P('source_data/originals'))
copy_tree(file.path(BASE,'FINAL_SUBMISSION_PACKAGE/R_code'),P('reproducibility/original_analysis_R'))
for(n in c('Clinical_and_data_tables','Raw_SSB_matrices'))copy_tree(file.path(BASE,'FINAL_SUBMISSION_PACKAGE',n),P('reproducibility',n))
copy_tree(file.path(BASE,'FINAL_SUBMISSION_PACKAGE/Manuscript'),P('archive_not_submitted/previous_manuscript_materials'))
copy_tree(file.path(BASE,'FINAL_SUBMISSION_PACKAGE/Tables'),P('archive_not_submitted/previous_tables'))
for(item in c('FINAL_SUBMISSION_PACKAGE/PowerPoint/SSB_All_Figures_editable_20261015.pptx','PPT_assembly_20261015/Slide_panel_index.tsv','PPT_assembly_20261015/qa/portrait_template.pptx')){
  nm<-c('SSB_All_Figures_editable_20261015.pptx'='Original_editable_figures.pptx','Slide_panel_index.tsv'='Original_PPT_panel_index.tsv','portrait_template.pptx'='portrait_template.pptx')[[basename(item)]]
  file.copy(file.path(BASE,item),P('source_panels',nm),overwrite=TRUE)
}
for(n in c('Main_figures','Supplementary_figures'))copy_tree(file.path(BASE,'FINAL_SUBMISSION_PACKAGE',n),P('archive_not_submitted/previous_composites',n))

panels<-data.table(new_id=character(),old_id=character(),subset=character(),figure=character(),tag=character())
add<-function(fig,newtags,oldids,subset=rep('',length(oldids))){stopifnot(length(newtags)==length(oldids));prefix<-if(grepl('^S',fig))paste0('Fig',fig)else paste0('Fig',sub('Figure','',fig));panels<<-rbind(panels,data.table(new_id=paste0(prefix,newtags),old_id=oldids,subset=subset,figure=fig,tag=newtags))}
add('Figure1',LETTERS[1:8],paste0('Fig1',LETTERS[1:8]))
add('Figure2',c(LETTERS[1:4],'E1','E2','E3','F','G','H'),c(paste0('Fig2',LETTERS[1:4]),paste0('Fig4A',1:3),'Fig2E','Fig2F','Fig2G'))
add('Figure3',LETTERS[1:6],paste0('Fig3',LETTERS[1:6]))
add('Figure4',LETTERS[1:8],c('Fig4B','Fig4C','Fig4D1','Fig4D2','Fig4E','Fig4F','Fig4G','Fig4H'))
add('S1',LETTERS[1:4],paste0('FigS1',LETTERS[1:4]))
add('S2','A','FigS25A')
add('S3',LETTERS[1:5],c(paste0('FigS3',LETTERS[1:4]),'FigS25B'))
for(i in 4:6)add(paste0('S',i),LETTERS[1:4],paste0('FigS',i,LETTERS[1:4]))
add('S7',LETTERS[1:4],c('FigS13A',paste0('FigS15',LETTERS[1:3])))
add('S8','A','FigS23A')
add('S9',LETTERS[1:3],c('Fig2H','Fig2I','Fig2I'),c('','CBC','detection'))
add('S10',LETTERS[1:3],paste0('FigS7',LETTERS[1:3]))
for(i in 1:4)add(paste0('S',10+i),LETTERS[1:4],paste0('FigS',18+i,LETTERS[1:4]))
add('S15','A','FigS24A')
add('S16',LETTERS[1:3],paste0('FigS8',LETTERS[1:3]))
add('S17','A','FigS28A')
add('S18',LETTERS[1:4],paste0('FigS9',LETTERS[1:4]))
add('S19',LETTERS[1:2],paste0('FigS12',LETTERS[1:2]))
add('S20',LETTERS[1:4],paste0('FigS10',LETTERS[1:4]))
add('S21','A','FigS26A','nonEXON')
add('S22',LETTERS[1:4],paste0('FigS16',LETTERS[1:4]))
add('S23',LETTERS[1:2],paste0('FigS17',LETTERS[1:2]))
add('S24',LETTERS[1:2],paste0('FigS18',LETTERS[1:2]))
add('S25',LETTERS[1:2],paste0('FigS11',LETTERS[1:2]))
stopifnot(nrow(panels)==107L,!anyDuplicated(panels$new_id),all(panels$old_id%in%names(origreg$captions)))
make_layout<-function(fig,rows,weights=rep(1,length(rows)),height=240){rh<-height*weights/sum(weights);yy<-c(0,head(cumsum(rh),-1L));rbindlist(lapply(seq_along(rows),function(i){ids<-rows[[i]];data.table(new_id=ids,left_mm=(seq_along(ids)-1)*183/length(ids),top_mm=yy[i],width_mm=183/length(ids),height_mm=rh[i])}))}
layouts<-list()
layouts$Figure1<-make_layout('Figure1',list('Fig1A',paste0('Fig1',LETTERS[2:5]),c('Fig1F','Fig1H'),'Fig1G'),c(.85,1.3,1.05,.85),250)
# Preserve the original dense-volcano canvas sizes for lossless DrawingML reuse.
layouts$Figure2<-make_layout('Figure2',list(c('Fig2A','Fig2B'),c('Fig2C','Fig2D'),paste0('Fig2E',1:3),c('Fig2F','Fig2G'),'Fig2H'),c(250*1.1/5.05,250*1.1/5.05,250*1.25/6.15,250*.75/5.05,1),250)
# Set the first four row heights exactly; the last row uses the remaining space.
rh<-c(250*1.1/5.05,250*1.1/5.05,250*1.25/6.15,250*.75/5.05)
layouts$Figure2<-make_layout('Figure2',list(c('Fig2A','Fig2B'),c('Fig2C','Fig2D'),paste0('Fig2E',1:3),c('Fig2F','Fig2G'),'Fig2H'),c(rh,250-sum(rh)),250)
layouts$Figure3<-make_layout('Figure3',list('Fig3A','Fig3B',c('Fig3C','Fig3D'),c('Fig3E','Fig3F')),c(1.1,.65,1.2,1.2),250)
layouts$Figure4<-make_layout('Figure4',list(c('Fig4A','Fig4B'),c('Fig4C','Fig4D'),c('Fig4E','Fig4F'),c('Fig4G','Fig4H')),c(1,1,1,1),250)
for(i in 1:25){fig<-paste0('S',i);ids<-panels[figure==fig,new_id];h<-if(i%in%c(1,16))250 else if(i==2)150 else 240
  rows<-if(i==1)list(ids[1],ids[2:3],ids[4])else if(i==3)list(ids[1:2],ids[3:4],ids[5])else if(i==7)list(ids[1],ids[2:4])else if(i==9)as.list(ids)else if(i==10)list(ids[1],ids[2:3])else if(i%in%c(16,21)||length(ids)<=2)as.list(ids)else split(ids,ceiling(seq_along(ids)/2))
  weights<-if(i==1)c(1.2,1.1,.8)else if(i==3)c(1,1,.8)else if(i==7)c(1,1)else if(i==9)c(1.2,.65,.9)else rep(1,length(rows))
  layouts[[fig]]<-make_layout(fig,rows,weights,h)
}
for(fig in names(layouts)){layouts[[fig]]<-merge(layouts[[fig]],panels[figure==fig,.(new_id,old_id,tag,subset)],by='new_id',sort=FALSE);stopifnot(setequal(layouts[[fig]]$new_id,panels[figure==fig,new_id]))}
dimensions<-data.table(figure=names(layouts),width_mm=183,height_mm=vapply(layouts,function(l)max(l$top_mm+l$height_mm),numeric(1)))
titles<-c(Figure1='Regional organization of peripheral-blood SSBs across healthy controls and cognitive-disorder groups',Figure2='Genomic SSB associations shared across cognitive disease and examined against Core 1 pathology',Figure3='Transcript architecture and functional context of the blood SSB atlas',Figure4='Internal discrimination and clinical relationships',
S1='Cohort definition and availability of clinical and biomarker records',S2='Regional Ri adjustment and cohort-relative context',S3='Age-related regional SSB summaries',S4='Core 1-positive versus HC feature associations',S5='Core 1-negative cognitive disorders versus HC feature associations',S6='Direct Core 1 pathology feature contrasts',S7='Regional detail for direct contrasts and shared association sets',S8='Participant-level organization of ranked EXON associations',S9='Technical robustness of broad cognitive-disease associations',S10='Biomarker-restricted and matched-population sensitivities',S11='Age-stratified GENE associations',S12='Age-stratified TSS200 associations',S13='Age-stratified INTRON associations',S14='Age-stratified EXON associations',S15='Exposure-normalized transcript-oriented density',S16='Transcript-position sensitivity profiles',S17='Adjusted transcript-region pathology effects',S18='Feature effects and annotation-union length',S19='Primary EXON mapping and functional annotation',S20='Additional internal model diagnostics and selection stability',S21='Clinical relationships of the complementary regional source scores',S22='Observed clinical measures and regional SSB summaries',S23='Clinical relationships of representative EXON associations',S24='Clinical relationships of pathology-model scores',S25='Exploratory clinical-stage associations')
saveRDS(list(panels=panels,layouts=layouts,dimensions=dimensions,titles=titles,original_registry=origreg),P('mapping_and_QC/figure_registry.rds'))
wr(panels,P('mapping_and_QC/submission_panel_registry.tsv'))
oldfiles<-list.files(P('source_panels/originals'),pattern='^Fig.*[.]rds$',full.names=FALSE)
oldids<-sub('[.]rds$','',oldfiles)
mapping<-merge(data.table(old_id=oldids),panels,by='old_id',all.x=TRUE,sort=FALSE)
mapping[,`:=`(old_figure=sub('([A-Z][0-9]*)$','',old_id),old_panel=sub('^Fig(?:S[0-9]+|[0-9]+)','',old_id,perl=TRUE),new_figure=figure,new_panel=tag,source_file=file.path('source_panels/originals',paste0(old_id,'.pdf')),final_file=ifelse(is.na(new_id),NA_character_,file.path('source_panels/submission',paste0(new_id,'.pdf'))),action=ifelse(is.na(new_id),'archive',ifelse(nzchar(subset),'subset without reanalysis','retain/relabel')),notes='')]
mapping[old_id%in%paste0('FigS14',LETTERS[1:4]),notes:='Exact regional Ri content repeated in main Figure 1B-E; archived.']
mapping[old_id%in%paste0('FigS2',LETTERS[1:4]),notes:='Upstream count/coordinate/annotation audit. Preserved with its source data; no independent result role in the revised clinical-atlas narrative.']
mapping[old_id=='FigS14E',notes:='Same adjusted regional effects as Figure 1G; numerical P detail remains in source data.']
mapping[old_id=='FigS15D',notes:='Primary EXON shared-set information already shown in main Figure 2F-H.']
mapping[old_id%in%c('FigS27A','FigS7D'),notes:='Absolute discovery-count view of the same robustness analyses; new S9 retains direction and corrected-association retention.']
mapping[old_id=='FigS8D',notes:='Historical copy of current FigS28A; current source retained as new S17A.']
mapping[old_id=='Fig3G',notes:='Unregistered historical enrichment layout, superseded by the approved six-panel Figure 3.']
mapping[old_id=='FigS26A',notes:='Only GENE/INTRON/TSS200 facets retained; duplicate primary EXON facet archived.']
mapping[,source_file:=normalizePath(P(source_file),mustWork=FALSE)]
wr(mapping[,.(old_figure,old_panel,new_figure,new_panel,source_file,final_file,action,notes)],P('mapping_and_QC/figure_panel_mapping.csv'))
sm<-mapping[grepl('^FigS',old_id),.(old_supplementary_id=old_id,new_supplementary_id=ifelse(is.na(new_id),'',new_id),scientific_topic=unname(titles[figure]),first_citation_section=ifelse(as.integer(sub('S','',figure))<=3,'Cohort definition and regional SSB architecture',ifelse(as.integer(sub('S','',figure))<=14,'A distributed exonic SSB signature characterizes cognitive disease',ifelse(as.integer(sub('S','',figure))<=19,'Transcript architecture and functional annotation add biological context','Blood SSB architecture contains strong disease-source information but little independent Core 1 separation'))),final_file=final_file,submit_or_archive=ifelse(is.na(new_id),'archive','submit'),notes=notes)]
wr(sm,P('mapping_and_QC/supplementary_renumbering.csv'))
for(id in unique(mapping[is.na(new_id)|old_id=='FigS26A',old_id])){dest<-P('archive_not_submitted/panels',id);dir.create(dest,recursive=TRUE,showWarnings=FALSE);for(ext in c('pdf','svg','tiff','png','rds')){f<-P('source_panels/originals',paste0(id,'.',ext));if(file.exists(f))file.copy(f,file.path(dest,basename(f)),overwrite=TRUE)}}
wr(data.table(source=c('Fig2H','Fig2I','FigS27A'),quantity=c('Direction + association retention after shared-interval exclusion','Direction + association retention under CBC/detection thresholds','Absolute higher/lower discovery counts across models'),decision=c('New S9A','New S9B-C','Archive alternative; not a substitute for direction/retention measures')),P('mapping_and_QC/technical_overlap_audit.tsv'))
for(ext in c('docx','xlsx'))file.copy(file.path(BASE,'FINAL_SUBMISSION_PACKAGE/Tables',paste0('Table1.',ext)),P('tables',paste0('Table_1.',ext)),overwrite=TRUE)
file.copy(file.path(BASE,'FINAL_SUBMISSION_PACKAGE/Tables/Supplementary_Data_1.xlsx'),P('supplementary_tables_or_data/Supplementary_Data_1.xlsx'),overwrite=TRUE)
file.copy(file.path(BASE,'FINAL_SUBMISSION_PACKAGE/Tables/Primary_EXON_heatmap_source.xlsx'),P('source_data/Ranked_EXON_heatmap_values.xlsx'),overwrite=TRUE)
wr(data.table(old_table_name=c('Table1.docx / Table1.xlsx','Supplementary_Data_1.xlsx','Primary_EXON_heatmap_source.xlsx'),new_table_number=c('Table 1','Supplementary Data 1','Source data only; not a separately numbered table'),first_citation=c('Opening Results paragraph','Primary EXON Results paragraph','Source for Supplementary Figure S8'),final_filename=c('tables/Table_1.docx; tables/Table_1.xlsx','supplementary_tables_or_data/Supplementary_Data_1.xlsx','source_data/Ranked_EXON_heatmap_values.xlsx')),P('mapping_and_QC/table_renumbering.csv'))
cat('MAPPING PASS: 4 main + 25 supplementary figures; 107 submitted panels. No statistical analysis executed.\n')
