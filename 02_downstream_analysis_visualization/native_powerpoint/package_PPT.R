# Add the verified figure deck to the existing submission package.
# Run only after assemble_all_figures.R has completed its full (not test) run.
root <- normalizePath(getwd())
.libPaths(c(file.path(dirname(root),'CI_atlas_revision_20260915/runtime/R_library'),
            file.path(dirname(root),'NOA_R_rebuild_20260821/R_library'),
            file.path(dirname(root),'runtime/R_libs'),.libPaths()))
suppressPackageStartupMessages(library(data.table))
src <- file.path(root,'PPT_assembly_20261015')
pkg <- file.path(root,'FINAL_SUBMISSION_PACKAGE')
dest <- file.path(pkg,'PowerPoint')
qa <- fread(file.path(src,'qa/PPTX_archive_QA.tsv'))
idx <- fread(file.path(src,'Slide_panel_index.tsv'))
stopifnot(nrow(qa)==32L,nrow(idx)==117L,all(qa$raster_pictures==0L),
          all(qa$duplicate_shape_ids==0L))
stopifnot(all(file.exists(file.path(src,idx$source_excel))),
          all(file.exists(file.path(src,idx$R_script))))
dir.create(dest,recursive=TRUE,showWarnings=FALSE)
files <- c('SSB_All_Figures_editable_20261015.pptx','assemble_all_figures.R','preview_headers.R','README.txt',
           'ASSEMBLY_CONTRACT.md','Makevars','qa/PPTX_archive_QA.tsv','qa/session_and_QA.txt',
           'qa/render_warnings.tsv','qa/Preview_header_QA.tsv')
files <- c(files,file.path('previews',list.files(file.path(src,'previews'),
                                                full.names=FALSE,pattern='^Figure[0-9_S]+\\.png$')),
           file.path('qa',list.files(file.path(src,'qa'),
                                     pattern='^Contact_sheet_[0-9]+\\.png$')))
for (f in files) {
  dir.create(dirname(file.path(dest,f)),recursive=TRUE,showWarnings=FALSE)
  stopifnot(file.copy(file.path(src,f),file.path(dest,f),overwrite=TRUE))
}
readme <- readLines(file.path(dest,'README.txt'))
readme <- sub("rvg 0.4.2 was installed in this folder's isolated R_library, not in the",
              'rvg 0.4.2 was installed in the separate assembly working R_library, not in the',readme,fixed=TRUE)
writeLines(readme,file.path(dest,'README.txt'))
# Make the copied source-data links unambiguous regardless of the index's folder.
idx[,source_excel:=normalizePath(file.path(src,source_excel))]
idx[,R_script:=normalizePath(file.path(src,R_script))]
fwrite(idx,file.path(dest,'Slide_panel_index.tsv'),sep='\t')
w <- openxlsx::createWorkbook()
openxlsx::addWorksheet(w,'Slide_panel_index')
openxlsx::writeData(w,'Slide_panel_index',idx)
openxlsx::freezePane(w,'Slide_panel_index',firstRow=TRUE)
openxlsx::setColWidths(w,'Slide_panel_index',1:9,14)
openxlsx::setColWidths(w,'Slide_panel_index',10:11,70)
openxlsx::addWorksheet(w,'Slide_summary')
openxlsx::writeData(w,'Slide_summary',idx[,.(panels=.N),by=.(slide,figure)])
openxlsx::saveWorkbook(w,file.path(dest,'Slide_panel_index.xlsx'),overwrite=TRUE)
delivery <- file.path(pkg,'DELIVERY_INDEX.xlsx')
dw <- openxlsx::loadWorkbook(delivery)
if('PowerPoint_slides'%in%names(dw))openxlsx::removeWorksheet(dw,'PowerPoint_slides')
openxlsx::addWorksheet(dw,'PowerPoint_slides')
slide_summary <- idx[,.(panels=.N,panel_identifiers=paste(panel,collapse=', ')),by=.(slide,figure)]
slide_summary[,PPTX:='PowerPoint/SSB_All_Figures_editable_20261015.pptx']
openxlsx::writeData(dw,'PowerPoint_slides',slide_summary)
openxlsx::setColWidths(dw,'PowerPoint_slides',1:3,15)
openxlsx::setColWidths(dw,'PowerPoint_slides',4:5,70)
openxlsx::freezePane(dw,'PowerPoint_slides',firstRow=TRUE)
openxlsx::saveWorkbook(dw,delivery,overwrite=TRUE)

# Existing submission checksums are preserved; only this addition and README
# are refreshed. This does not reread or modify clinical/statistical datasets.
checkfile <- file.path(pkg,'FILE_CHECKSUMS.tsv')
checks <- fread(checkfile)
checks <- checks[!grepl('^PowerPoint/',file) & !file%in%c('README.txt','DELIVERY_INDEX.xlsx')]
add <- c('README.txt','DELIVERY_INDEX.xlsx',file.path('PowerPoint',list.files(dest,recursive=TRUE,full.names=FALSE)))
extra <- data.table(file=add,bytes=file.info(file.path(pkg,add))$size,
                    md5=unname(tools::md5sum(file.path(pkg,add))))
fwrite(rbindlist(list(checks,extra))[order(file)],checkfile,sep='\t',quote=TRUE)
stopifnot(identical(unname(tools::md5sum(file.path(src,files[1]))),
                    unname(tools::md5sum(file.path(dest,files[1])))))
cat('PACKAGED:',file.path(dest,files[1]),'\n')
