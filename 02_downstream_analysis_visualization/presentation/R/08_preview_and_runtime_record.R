source('R/00_common.R')
pkgs<-c('ggplot2','data.table','openxlsx','officer','rvg','xml2','svglite','ragg','png','zip')
stopifnot(all(vapply(pkgs,requireNamespace,logical(1),quietly=TRUE)))
versions<-data.table(package=pkgs,version=vapply(pkgs,function(x)as.character(utils::packageVersion(x)),character(1)))
wr(versions,P('mapping_and_QC/package_versions.tsv'))
capture.output(sessionInfo(),file=P('mapping_and_QC/sessionInfo.txt'))
reg<-readRDS(P('mapping_and_QC/figure_registry.rds'))
# Refresh the small entry points mechanically; this performs no rendering or inference.
for(id in reg$panels$new_id)writeLines(c("Sys.unsetenv(c('SSB_RENDER_FIGURES','SSB_VECTOR_ONLY'))",paste0("Sys.setenv(SSB_SINGLE_PANEL='",id,"')"),"source('R/02_render_figures.R')"),P('R/panels',paste0(id,'.R')))
for(fig in names(reg$layouts))writeLines(c("Sys.unsetenv(c('SSB_SINGLE_PANEL','SSB_VECTOR_ONLY'))",paste0("Sys.setenv(SSB_RENDER_FIGURES='",fig,"')"),"source('R/06_render_composites_only.R')"),P('R/figures',paste0(fig,'.R')))
image_path<-function(fig)if(grepl('^S',fig))P('supplementary_figures',paste0('Supplementary_Figure_',fig,'.png'))else P('main_figures',paste0(sub('Figure','Figure_',fig),'.png'))
contact<-function(figs,file,ncol=2L){
  nrow<-ceiling(length(figs)/ncol)
  cell_w<-850;cell_h<-1230
  ragg::agg_png(file,width=cell_w*ncol,height=cell_h*nrow,units='px',res=120,background='white')
  grid.newpage()
  for(i in seq_along(figs)){
    col<-(i-1L)%%ncol;row<-(i-1L)%/%ncol
    pushViewport(viewport(x=col/ncol,y=1-row/nrow,width=1/ncol,height=1/nrow,just=c('left','top')))
    grid.text(if(grepl('^S',figs[i]))paste('Supplementary Figure',figs[i])else sub('Figure','Figure ',figs[i]),x=.025,y=.99,just=c('left','top'),gp=gpar(fontfamily='Arial',fontsize=16,fontface='bold'))
    im<-png::readPNG(image_path(figs[i]));ar<-dim(im)[1]/dim(im)[2]
    hh<-min(.94,(cell_w*.97/cell_h)*ar);ww<-hh*cell_h/cell_w/ar
    grid.raster(im,x=.5,y=.48,width=ww,height=hh,interpolate=TRUE)
    grid.rect(gp=gpar(col='#D0D0D0',fill=NA))
    upViewport(0)
  }
  dev.off()
}
contact(paste0('Figure',1:4),P('previews/contact_sheet_main.png'))
sets<-split(paste0('S',1:25),ceiling((1:25)/6))
for(i in seq_along(sets))contact(sets[[i]],P('previews',sprintf('contact_sheet_supplementary_%02d.png',i)))
original<-P('author_inputs/Manuscript_author_revised_EN.md')
revised<-P('manuscript/Manuscript_SSB_revised_full_EN_renumbered.md')
if(nzchar(Sys.which('diff')))invisible(system2('diff',c('-u',shQuote(original),shQuote(revised)),stdout=P('mapping_and_QC/manuscript_changes.diff'),stderr=FALSE))
cat('RUNTIME AND PREVIEW RECORD COMPLETE: no numerical analysis performed.\n')
