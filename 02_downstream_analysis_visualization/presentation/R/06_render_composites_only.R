# Recompose approved panels without re-exporting source workbooks or statistics.
source('R/00_common.R')
reg<-readRDS(P('mapping_and_QC/figure_registry.rds'))
for(ex in parse('R/02_render_figures.R'))if(is.call(ex)&&identical(ex[[1]],as.name('<-'))&&identical(ex[[2]],as.name('render_one')))eval(ex)
selected<-Sys.getenv('SSB_RENDER_FIGURES',unset='')
figs<-if(nzchar(selected))intersect(strsplit(selected,',',fixed=TRUE)[[1]],names(reg$layouts))else names(reg$layouts)
cores<-min(6L,max(1L,as.integer(Sys.getenv('SSB_RENDER_WORKERS',unset='4'))))
r<-parallel::mclapply(figs,render_one,mc.cores=cores,mc.preschedule=FALSE)
stopifnot(!any(vapply(r,inherits,logical(1),'try-error')))
for(kind in c('main','supplementary')){
  keep<-names(reg$layouts)[if(kind=='main')!grepl('^S',names(reg$layouts))else grepl('^S',names(reg$layouts))]
  cairo_pdf(P(paste0(kind,'_figures'),paste0('All_',kind,'_figures.pdf')),width=183/25.4,height=250/25.4,family='Arial',onefile=TRUE)
  for(fig in keep)draw_figure(fig);dev.off()
}
cat('COMPOSITES PASS:',length(figs),'figures.\n')
