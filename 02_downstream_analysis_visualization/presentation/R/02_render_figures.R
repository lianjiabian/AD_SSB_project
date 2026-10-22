source('R/00_common.R')
reg<-readRDS(P('mapping_and_QC/figure_registry.rds'))
stopifnot(all(vapply(c('svglite','ragg','openxlsx'),requireNamespace,logical(1),quietly=TRUE)))
render_one<-function(fig){
  wh<-reg$dimensions[figure==fig];dir<-if(grepl('^S',fig))'supplementary_figures'else'main_figures'
  stem<-if(grepl('^S',fig))paste0('Supplementary_Figure_',fig)else sub('Figure','Figure_',fig)
  f<-P(dir,stem)
  grDevices::cairo_pdf(paste0(f,'.pdf'),width=wh$width_mm/25.4,height=wh$height_mm/25.4,family='Arial');draw_figure(fig);dev.off()
  svglite::svglite(paste0(f,'.svg'),width=wh$width_mm/25.4,height=wh$height_mm/25.4);draw_figure(fig);dev.off()
  ragg::agg_tiff(paste0(f,'.tiff'),width=wh$width_mm,height=wh$height_mm,units='mm',res=600,compression='lzw');draw_figure(fig);dev.off()
  ragg::agg_png(paste0(f,'.png'),width=wh$width_mm,height=wh$height_mm,units='mm',res=160);draw_figure(fig);dev.off()
  cat('FIGURE',fig,'\n');invisible(fig)
}
selected<-Sys.getenv('SSB_RENDER_FIGURES',unset='')
if(nzchar(selected)){
  figs<-intersect(strsplit(selected,',',fixed=TRUE)[[1]],names(reg$layouts))
}else figs<-names(reg$layouts)
if(Sys.getenv('SSB_SINGLE_PANEL',unset='')==''&&Sys.getenv('SSB_VECTOR_ONLY')!='1'){
  workers<-as.integer(Sys.getenv('SSB_RENDER_WORKERS',unset='4'));workers<-min(6L,max(1L,workers))
  res<-parallel::mclapply(figs,render_one,mc.cores=workers,mc.preschedule=FALSE)
  stopifnot(!any(vapply(res,inherits,logical(1),'try-error')))
}
ids<-reg$panels$new_id
single<-Sys.getenv('SSB_SINGLE_PANEL',unset='');if(nzchar(single))ids<-intersect(ids,single)
if(Sys.getenv('SSB_VECTOR_ONLY')=='1')ids<-ids[vapply(ids,function(id){r<-reg$panels[new_id==id];f<-P('source_panels/originals',paste0(r$old_id,'.svg'));any(grepl('<image',readLines(f,warn=FALSE),fixed=TRUE))},logical(1))]
for(id in ids){
  r<-reg$panels[new_id==id];orig<-P('source_panels/originals',r$old_id);dest<-P('source_panels/submission',id)
  oldsvg<-paste0(orig,'.svg');has_raster_key<-file.exists(oldsvg)&&any(grepl('<image',readLines(oldsvg,warn=FALSE),fixed=TRUE))
  if(!nzchar(r$subset)&&!has_raster_key&&id!='FigS20B')for(ext in c('pdf','svg','tiff','png','rds'))stopifnot(file.copy(paste0(orig,'.',ext),paste0(dest,'.',ext),overwrite=TRUE))
  else{
    p<-load_panel(id,12);assign('d',p$data,envir=.GlobalEnv)
    if(r$old_id=='FigS23A')assign('aa',read_source('FigS23A','statistics'),envir=.GlobalEnv)
    w<-if(r$subset=='nonEXON')200 else 183;h<-if(r$subset=='nonEXON')250 else if(has_raster_key||id=='FigS20B')if(r$old_id=='FigS28A')210 else 160 else 105
    cairo_pdf(paste0(dest,'.pdf'),width=w/25.4,height=h/25.4,family='Arial');print(p);dev.off()
    svglite::svglite(paste0(dest,'.svg'),width=w/25.4,height=h/25.4);print(p);dev.off()
    ragg::agg_tiff(paste0(dest,'.tiff'),width=w,height=h,units='mm',res=600,compression='lzw');print(p);dev.off()
    ragg::agg_png(paste0(dest,'.png'),width=w,height=h,units='mm',res=160);print(p);dev.off();saveRDS(p,paste0(dest,'.rds'))
  }
  dd<-read_source(r$old_id);st<-read_source(r$old_id,'statistics');pa<-read_source(r$old_id,'participants')
  if(r$subset=='CBC'){dd<-dd[model=='A_CBC'];st<-st[model=='A_CBC'];if('model'%in%names(pa))pa<-pa[model=='A_CBC']}
  if(r$subset=='detection'){dd<-dd[model%in%c('A_detection10','A_detection30')];st<-st[model%in%c('A_detection10','A_detection30')];if('model'%in%names(pa))pa<-pa[model%in%c('A_detection10','A_detection30')]}
  if(r$subset=='nonEXON'){if('region'%in%names(dd))dd<-dd[region!='EXON'];if('region'%in%names(st))st<-st[region!='EXON'];if('region'%in%names(pa))pa<-pa[region!='EXON']}
  outdir<-P('source_data/panels',id);dir.create(outdir,recursive=TRUE,showWarnings=FALSE)
  for(nm in c('plot_data','statistics','participants'))wr(get(c(plot_data='dd',statistics='st',participants='pa')[[nm]]),file.path(outdir,paste0(nm,'.tsv')))
  wb<-openxlsx::createWorkbook();openxlsx::modifyBaseFont(wb,fontName='Arial',fontSize=10)
  tabs<-list(Readme=data.table(panel=id,original_source=r$old_id,subset=r$subset,statistical_reanalysis='None'),Plot_data=dd,Statistics=st,Participants=pa)
  for(nm in names(tabs)){openxlsx::addWorksheet(wb,nm);openxlsx::writeData(wb,nm,as.data.frame(tabs[[nm]]));openxlsx::freezePane(wb,nm,firstRow=TRUE)}
  openxlsx::saveWorkbook(wb,P('source_data/panels',paste0(id,'_source_data.xlsx')),overwrite=TRUE)
  writeLines(c("Sys.unsetenv(c('SSB_RENDER_FIGURES','SSB_VECTOR_ONLY'))",paste0("Sys.setenv(SSB_SINGLE_PANEL='",id,"')"),"source('R/02_render_figures.R')"),P('R/panels',paste0(id,'.R')))
}
if(!nzchar(single)&&Sys.getenv('SSB_VECTOR_ONLY')!='1'){
  for(fig in names(reg$layouts))writeLines(c("Sys.unsetenv(c('SSB_SINGLE_PANEL','SSB_VECTOR_ONLY'))",paste0("Sys.setenv(SSB_RENDER_FIGURES='",fig,"')"),"source('R/06_render_composites_only.R')"),P('R/figures',paste0(fig,'.R')))
  # Combined vector PDFs are convenience compilations of already cited figures.
  for(kind in c('main','supplementary')){
    keep<-names(reg$layouts)[if(kind=='main')!grepl('^S',names(reg$layouts))else grepl('^S',names(reg$layouts))]
    cairo_pdf(P(paste0(kind,'_figures'),paste0('All_',kind,'_figures.pdf')),width=183/25.4,height=250/25.4,family='Arial',onefile=TRUE)
    for(fig in keep)draw_figure(fig);dev.off()
  }
}
cat('RENDER PASS: only existing panel objects/data were plotted.\n')
