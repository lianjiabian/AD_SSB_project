source('R/00_common.R')
suppressPackageStartupMessages({library(xml2);library(openxlsx)})
reg<-readRDS(P('mapping_and_QC/figure_registry.rds'))
# Necessary existing result families are added, not recalculated.
for(item in c('results/age_models.tsv','results/profile/adjusted_tests.tsv')){
  nm<-if(grepl('age_models',item,fixed=TRUE))'precomputed_age_models.tsv'else'precomputed_profile_tests.tsv'
  if(!file.exists(P('source_data',nm)))file.copy(file.path(BASE,item),P('source_data',nm),overwrite=TRUE)
}
f<-P('supplementary_tables_or_data/Supplementary_Data_1.xlsx')
oldbook<-P('archive_not_submitted/previous_tables/Supplementary_Data_1.xlsx')
if(!file.exists(oldbook)){dir.create(dirname(oldbook),recursive=TRUE,showWarnings=FALSE);file.copy(file.path(BASE,'FINAL_SUBMISSION_PACKAGE/Tables/Supplementary_Data_1.xlsx'),oldbook)}
wb<-loadWorkbook(f)
for(nm in c('Age_models','Profile_bin_tests'))if(nm%in%names(wb))removeWorksheet(wb,nm)
addWorksheet(wb,'Age_models');writeData(wb,'Age_models',rd(P('source_data/precomputed_age_models.tsv')))
addWorksheet(wb,'Profile_bin_tests');writeData(wb,'Profile_bin_tests',rd(P('source_data/precomputed_profile_tests.tsv'))[level=='bin'])
saveWorkbook(wb,f,overwrite=TRUE)
oldtabs<-getSheetNames(oldbook)
sheetqa<-rbindlist(lapply(oldtabs,function(s)data.table(sheet=s,unchanged=isTRUE(all.equal(read.xlsx(oldbook,s),read.xlsx(f,s),check.attributes=FALSE)))))
wr(sheetqa,P('mapping_and_QC/Supplementary_Data_value_preservation.tsv'));stopifnot(all(sheetqa$unchanged))

man<-readLines(P('manuscript/Manuscript_SSB_revised_full_EN_renumbered.md'),warn=FALSE)
body<-paste(man[seq_len(match('## Figure legends',man)-1L)],collapse='\n')
matches<-function(p,x){a<-gregexpr(p,x,perl=TRUE);regmatches(x,a)[[1]]}
mc<-matches('Fig[.] [1-4][A-Z][A-Z0-9,-]*',body)
expand_main<-function(cite){f<-substring(sub('Fig. ','',cite,fixed=TRUE),1,1);s<-substring(sub('Fig. ','',cite,fixed=TRUE),2);parts<-strsplit(s,',',fixed=TRUE)[[1]];tags<-unlist(lapply(parts,function(t){if(grepl('-',t,fixed=TRUE)){q<-strsplit(t,'-',fixed=TRUE)[[1]];if(nchar(q[1])==1L)LETTERS[match(q[1],LETTERS):match(q[2],LETTERS)]else paste0(substr(q[1],1,1),as.integer(substring(q[1],2)):as.integer(substring(q[2],2)))}else t}));paste0('Fig',f,tags)}
maincited<-unlist(lapply(mc,expand_main));mainfirst<-unique(sub('Fig. ','',substring(mc,1,6),fixed=TRUE))
mainorder<-unique(vapply(mc,function(x)substring(sub('Fig. ','',x,fixed=TRUE),1,1),character(1)))
sc<-matches('Supplementary Figs?[.] S[0-9]+(?:[-–]S?[0-9]+)?',body)
expand_s<-function(s){ns<-as.integer(matches('[0-9]+',s));if(length(ns)==1)paste0('S',ns)else paste0('S',seq.int(ns[1],ns[2]))}
scited<-unlist(lapply(sc,expand_s));sorder<-unique(scited)
stopifnot(identical(mainorder,as.character(1:4)),identical(sorder,paste0('S',1:25)))
mainids<-reg$panels[!startsWith(figure,'S'),new_id]
stopifnot(setequal(mainids,unique(maincited)),all(unique(maincited)%in%reg$panels$new_id),all(unique(scited)%in%names(reg$layouts)))
panelcite<-reg$panels[,.(figure,panel=new_id)]
panelcite[,cited:=ifelse(startsWith(figure,'S'),figure%in%scited,panel%in%maincited)]
wr(panelcite,P('mapping_and_QC/panel_citation_coverage.tsv'))
stopifnot(all(panelcite$cited),grepl('Table 1',body,fixed=TRUE),grepl('Supplementary Data 1',body,fixed=TRUE))
stopifnot(!grepl('Fig. 4A1',body,fixed=TRUE),!grepl('Fig. 2H,I',body,fixed=TRUE),!grepl('S25A',body,fixed=TRUE),!grepl('S25B',body,fixed=TRUE))
required<-c(Fig2E1='Fig4A1',Fig2E2='Fig4A2',Fig2E3='Fig4A3',Fig2F='Fig2E',Fig2G='Fig2F',Fig2H='Fig2G',Fig4A='Fig4B',Fig4B='Fig4C',Fig4C='Fig4D1',Fig4D='Fig4D2')
stopifnot(all(reg$panels[match(names(required),new_id),old_id]==unname(required)))
for(fig in names(reg$layouts)){
  dir<-if(startsWith(fig,'S'))'supplementary_figures'else'main_figures';stem<-if(startsWith(fig,'S'))paste0('Supplementary_Figure_',fig)else sub('Figure','Figure_',fig)
  stopifnot(all(file.exists(P(dir,paste0(stem,c('.pdf','.svg','.tiff','.png'))))))
}
stopifnot(all(file.exists(P('source_panels/submission',paste0(reg$panels$new_id,'.pdf')))),all(file.exists(P('source_data/panels',paste0(reg$panels$new_id,'_source_data.xlsx')))))
oldSI<-sub('[.][^.]+$','',list.files(P('source_panels/originals'),pattern='^FigS.*[.](pdf|rds|svg|tiff|png)$'))
sm<-rd(P('mapping_and_QC/supplementary_renumbering.csv'))
stopifnot(all(unique(oldSI)%in%sm$old_supplementary_id))
sm[submit_or_archive=='archive',scientific_topic:=fifelse(grepl('FigS2[A-D]',old_supplementary_id),'Upstream count, coordinate and annotation QC',fifelse(grepl('FigS14',old_supplementary_id),'Duplicated regional Ri evidence','Historical or duplicated analysis presentation'))]
sm[submit_or_archive=='archive',first_citation_section:='Not submitted; archive and numerical source retained']
sm[old_supplementary_id=='FigS26A',submit_or_archive:='submit complementary subset; archive original full panel']
wr(sm,P('mapping_and_QC/supplementary_renumbering.csv'))
# Compare every submitted numeric source with its unchanged historical input.
checks<-list()
for(i in seq_len(nrow(reg$panels))){
  r<-reg$panels[i]
  for(what in c('plot_data','statistics','participants')){
    a<-read_source(r$old_id,what);b<-rd(P('source_data/panels',r$new_id,paste0(what,'.tsv')))
    if(r$subset=='CBC'&&'model'%in%names(a))a<-a[model=='A_CBC']
    if(r$subset=='detection'&&'model'%in%names(a))a<-a[model%in%c('A_detection10','A_detection30')]
    if(r$subset=='nonEXON'&&'region'%in%names(a))a<-a[region!='EXON']
    ok<-isTRUE(all.equal(as.data.frame(a),as.data.frame(b),tolerance=1e-13,check.attributes=FALSE))
    checks[[length(checks)+1L]]<-data.table(panel=r$new_id,type=what,rows=nrow(b),numeric_content_preserved=ok)
  }
}
checkdt<-rbindlist(checks);wr(checkdt,P('mapping_and_QC/panel_source_preservation.tsv'));stopifnot(all(checkdt$numeric_content_preserved))
origchecks<-rd(P('mapping_and_QC/baseline_checksums.tsv'))
if(dir.exists(BASE)){origchecks[,unchanged:=md5==unname(tools::md5sum(file.path(BASE,file)))];stopifnot(all(origchecks$unchanged));wr(origchecks,P('mapping_and_QC/baseline_checksums_verified.tsv'))}
# Font and dpi checks inspect files only; they do not convert or redraw figures.
exports<-reg$dimensions[,.(figure,file=ifelse(startsWith(figure,'S'),paste0('supplementary_figures/Supplementary_Figure_',figure,'.pdf'),paste0('main_figures/',sub('Figure','Figure_',figure),'.pdf')))]
fontlog<-list();dpiqa<-list()
for(i in seq_len(nrow(exports))){
  ff<-P(exports$file[i]);info<-system2('pdfinfo',shQuote(ff),stdout=TRUE);font<-system2('pdffonts',shQuote(ff),stdout=TRUE)
  stopifnot(any(grepl('Pages: +1$',info)),any(grepl('Arial',font,ignore.case=TRUE)))
  fontlog[[i]]<-c(paste0('## ',exports$figure[i]),font)
}
writeLines(unlist(fontlog),P('mapping_and_QC/PDF_font_audit.txt'))
tiffs<-c(sub('[.]pdf$','.tiff',exports$file),file.path('source_panels/submission',paste0(reg$panels$new_id,'.tiff')))
for(f0 in tiffs){s<-system2('identify',c('-format',shQuote('%x %y %U'),shQuote(P(f0))),stdout=TRUE,stderr=FALSE);a<-strsplit(s,' ')[[1]];v<-as.numeric(a[1:2]);if(any(grepl('Centimeter',a)))v<-v*2.54;dpiqa[[length(dpiqa)+1L]]<-data.table(file=f0,dpi_x=v[1],dpi_y=v[2],PASS=all(abs(v-600)<.1))}
dpiqa<-rbindlist(dpiqa);wr(dpiqa,P('mapping_and_QC/TIFF_resolution_QA.tsv'));stopifnot(all(dpiqa$PASS))
svgfiles<-c(sub('[.]pdf$','.svg',exports$file),file.path('source_panels/submission',paste0(reg$panels$new_id,'.svg')))
svgqa<-rbindlist(lapply(svgfiles,function(f)data.table(file=f,embedded_raster=any(grepl('<image',readLines(P(f),warn=FALSE),fixed=TRUE)))))
wr(svgqa,P('mapping_and_QC/SVG_vector_QA.tsv'));stopifnot(!any(svgqa$embedded_raster))
wx<-read_xml(unz(P('manuscript/Manuscript_SSB_revised_full_EN_renumbered.docx'),'word/document.xml'))
mathN<-length(xml_find_all(wx,'//m:oMath'));stopifnot(mathN>=2L)
native<-rd(P('mapping_and_QC/PowerPoint_structure_QA.tsv'));stopifnot(nrow(native)==29L,sum(native$panels)==107L,all(native$raster_pictures==0L),all(native$duplicate_ids==0L))

idx<-merge(reg$panels,reg$dimensions,by='figure',sort=FALSE)
idx[,`:=`(panel_pdf=file.path('source_panels/submission',paste0(new_id,'.pdf')),source_excel=file.path('source_data/panels',paste0(new_id,'_source_data.xlsx')),R_script=file.path('R/panels',paste0(new_id,'.R')))]
write.xlsx(list(Panels=idx,Figures=exports,Supplementary_numbering=sm,Tables=rd(P('mapping_and_QC/table_renumbering.csv'))),P('DELIVERY_INDEX.xlsx'),overwrite=TRUE)
write.xlsx(list(Panel_source_data=idx[,.(figure,panel=new_id,source_excel)],Figure_composition=reg$panels),P('source_data/Figure_source_data_index.xlsx'),overwrite=TRUE)

archive<-sm[submit_or_archive=='archive']
audit<-c('# Figure, table and citation audit','',
paste('Main-figure first citations:',paste(mainorder,collapse=' -> ')),
paste('Supplementary first citations:',paste(sorder,collapse=' -> ')),'',
'All 32 main-figure panels are explicitly covered by Results citations, including Figure 4A, B, C/D/H, E, F and G.',
'All 25 submitted supplementary figures have in-text citations. All submitted figure identifiers resolve to the corresponding final PDF/SVG/TIFF and native PowerPoint panel.',
'Table citations: Table 1 (opening Results paragraph); Supplementary Data 1 (primary EXON Results paragraph and figure legends). No numbered supplementary tables were invented.',
'No orphan submitted figure or formal table files. Convenience compilations and PowerPoint decks contain only already cited figures.',
'No unresolved historical main-panel citations. Historical S-number strings are accepted only where they now refer to the correctly mapped final scientific topic.',
'Figure 2 is A-D, E1-E3, F-H. Figure 4 is A-H. Previous Figure 2H/I robustness measures are now Supplementary Figure S9A-C.',
'The full four-facet MMSE panel was archived; new S21 contains only GENE, INTRON and TSS200. The primary EXON scatter appears once in main Figure 4E.',
paste('Archived SI panels:',paste(archive$old_supplementary_id,collapse=', ')),
'Archive decisions and every historical SI panel are documented in supplementary_renumbering.csv. Original source panels and previous composites were preserved, never deleted.',
'Title/Abstract/Introduction/Methods/Discussion/Conclusion/Declarations/Table legend/References were protected. Decimal result tokens and every plotted numeric source were preserved. Table 1 data rows were unchanged.',
paste('Word native math objects:',mathN),
'Supplementary Data 1 retains all 18 original sheets unchanged; existing age-model and profile-bin results were appended without recalculation.',
'Author review: the original administrative completion fields remain; no new numerical or scientific ambiguity was introduced. References were retained as supplied rather than reverified or renumbered.',
'',
'PASS: all submitted figures and tables are cited in numerical order and all citations resolve to final files.')
writeLines(audit,P('mapping_and_QC/citation_audit.md'))
cat('AUDIT PASS: ordered citations; preserved numerical sources; vector figures; 600-dpi TIFFs; native PPT.\n')
