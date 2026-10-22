options(stringsAsFactors=FALSE)
ROOT<-Sys.getenv('SSB_REVISION_ROOT',unset=normalizePath(getwd()))
BASE<-Sys.getenv('SSB_BASELINE_ROOT',unset='/inputs/ssb_study/SSB_QC261_EXON_primary_20261013')
.libPaths(c(file.path(BASE,'PPT_assembly_20261015/R_library'),file.path(dirname(BASE),'CI_atlas_revision_20260915/runtime/R_library'),file.path(dirname(BASE),'NOA_R_rebuild_20260821/R_library'),file.path(dirname(BASE),'runtime/R_libs'),.libPaths()))
suppressPackageStartupMessages({library(data.table);library(ggplot2);library(grid)})
setDTthreads(1L);Sys.setenv(OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',MKL_NUM_THREADS='1')
P<-function(...)file.path(ROOT,...)
rd<-function(f)fread(f,na.strings=c('','NA'),showProgress=FALSE)
wr<-function(x,f){dir.create(dirname(f),recursive=TRUE,showWarnings=FALSE);fwrite(x,f,sep=if(grepl('[.]csv$',f))','else'\t',na='NA')}
G3<-c('HC','Core 1-positive AD pathology','Core 1-negative cognitive disorders')
SPACES<-c('GENE','TSS200','INTRON','EXON')
COL<-c(HC='#3C5488','Disease-source'='#C17C3B','Core 1-positive AD pathology'='#8064A2','Core 1-negative cognitive disorders'='#E69F00')
fmtp<-function(p)ifelse(is.na(p),'NA',ifelse(p==0,'<2.2e-16',ifelse(p<.001,formatC(p,format='e',digits=1),sprintf('%.3f',p))))
short_axis<-function(v){dict<-c(setNames(c('HC','AD','Other'),G3),Positive_vs_HC='AD vs HC',Negative_vs_HC='Other vs HC',Positive_vs_Negative='AD vs Other',A_CBC='Blood cells',A_detection10='Detection 10%',A_detection30='Detection 30%',A_primary='Primary',A_unshared='Unshared');ifelse(v%in%names(dict),unname(dict[v]),v)}
for(d in c('main_figures','supplementary_figures','tables','supplementary_tables_or_data','source_panels/originals','source_panels/submission','source_data/panels','source_data/figures','archive_not_submitted','mapping_and_QC','manuscript','R/panels','R/figures','author_inputs','reproducibility','powerpoint','previews'))dir.create(P(d),recursive=TRUE,showWarnings=FALSE)
copy_tree<-function(from,to){dir.create(to,recursive=TRUE,showWarnings=FALSE);fs<-list.files(from,recursive=TRUE,full.names=FALSE,all.files=TRUE,no..=TRUE);fs<-fs[!file.info(file.path(from,fs))$isdir];for(f in fs){dir.create(dirname(file.path(to,f)),recursive=TRUE,showWarnings=FALSE);if(!file.exists(file.path(to,f)))stopifnot(file.copy(file.path(from,f),file.path(to,f),copy.date=TRUE))};invisible(fs)}
read_source<-function(id,what='plot_data'){f<-P('source_data/originals',id,paste0(what,'.tsv'));if(!file.exists(f))f<-file.path(BASE,'source_data',id,paste0(what,'.tsv'));rd(f)}
load_panel<-function(id,size=8.5){
  z<-readRDS(P('mapping_and_QC/figure_registry.rds'));r<-z$panels[new_id==id];stopifnot(nrow(r)==1)
  p<-readRDS(P('source_panels/originals',paste0(r$old_id,'.rds')))
  pd<-if(is.data.frame(p$data))as.data.table(p$data)else data.table()
  if(r$subset=='CBC')p<-p%+%pd[model=='A_CBC']
  if(r$subset=='detection')p<-p%+%pd[model%in%c('A_detection10','A_detection30')]
  if(r$subset=='nonEXON'){
    p<-p%+%pd[region!='EXON']
    for(k in seq_along(p$layers))if(is.data.frame(p$layers[[k]]$data)&&'region'%in%names(p$layers[[k]]$data)){ld<-p$layers[[k]]$data;p$layers[[k]]$data<-ld[ld$region!='EXON',]}
    p<-p+facet_wrap(~region,ncol=1)
  }
  if(r$subset%in%c('CBC','detection'))p<-p+labs(title=if(r$subset=='CBC')'Blood-cell adjustment'else'Detection thresholds')
  if(r$old_id%in%paste0('FigS15',LETTERS[1:3])&&size<12)p<-p+theme(axis.text.x=element_text(angle=60,hjust=1))
  # Only text presentation is resized; no model, effect, P value or ranking is recomputed.
  if(size!=12){
    for(k in seq_along(p$layers))if(inherits(p$layers[[k]]$geom,c('GeomText','GeomLabel'))){s<-p$layers[[k]]$aes_params$size;if(!is.null(s))p$layers[[k]]$aes_params$size<-s*size/12}
    pm<-p$theme$plot.margin
    if(!is.null(pm)&&all(as.numeric(pm)==6))p<-p+theme(plot.margin=margin(size/2,size/2,size/2,size/2))
  }
  p<-p+labs(tag=NULL)+theme(text=element_text(family='Arial',size=size),axis.text=element_text(size=size),axis.title=element_text(size=size),strip.text=element_text(size=size),legend.text=element_text(size=size),plot.title=element_text(size=size,face='bold'),plot.subtitle=element_text(size=size),plot.caption=element_text(size=size),plot.tag=element_text(size=size,face='bold'))
  if(id=='Fig2H')p<-p+guides(colour=guide_legend(nrow=1))
  if(id=='Fig4C')p<-p+guides(colour=guide_legend(ncol=2))
  if(id=='FigS20A')p<-p+guides(colour=guide_legend(ncol=2))
  if(id=='FigS20B')p<-p+guides(colour=guide_legend(ncol=2,order=1),size=guide_legend(ncol=3,order=2))+theme(legend.box='vertical')
  for(a in c('fill','colour')){sc<-p$scales$get_scales(a);if(!is.null(sc)&&!sc$is_discrete()){gd<-p$guides$get_guide(a);if(!(is.character(gd)&&identical(gd,'none'))&&!inherits(gd,'GuideNone')){if(a=='fill')p<-p+guides(fill=guide_colourbar(display='rectangles'))else p<-p+guides(colour=guide_colourbar(display='rectangles'))}}}
  p
}
draw_panel<-function(p,tag,size=8.5,newpage=TRUE){
  if(newpage)grid.newpage()
  # The plot-data object named d is used by two serialized factor-order expressions.
  assign('d',p$data,envir=.GlobalEnv)
  if('gene_name'%in%names(p$data)&&'sample_order'%in%names(p$data))assign('aa',read_source('FigS23A','statistics'),envir=.GlobalEnv)
  pushViewport(viewport(x=0,y=0,width=1,height=unit(1,'npc')-unit(3,'mm'),just=c('left','bottom')))
  grid.draw(ggplotGrob(p));popViewport()
  grid.text(tag,x=unit(.5,'mm'),y=unit(1,'npc')-unit(.4,'mm'),just=c('left','top'),gp=gpar(fontfamily='Arial',fontsize=size,fontface='bold'))
}
draw_figure<-function(fig){
  z<-readRDS(P('mapping_and_QC/figure_registry.rds'));lay<-z$layouts[[fig]];wh<-z$dimensions[figure==fig];grid.newpage()
  for(j in seq_len(nrow(lay))){b<-lay[j];p<-load_panel(b$new_id,8.5);pushViewport(viewport(x=unit(b$left_mm,'mm'),y=unit(wh$height_mm-b$top_mm,'mm'),width=unit(b$width_mm,'mm'),height=unit(b$height_mm,'mm'),just=c('left','top')));draw_panel(p,b$tag,newpage=FALSE);upViewport(0)}
  # Draw all header strips last to avoid cross-viewport clipping in previews.
  pushViewport(viewport(clip='off'))
  for(j in seq_len(nrow(lay))){b<-lay[j];grid.rect(x=unit(b$left_mm,'mm'),y=unit(wh$height_mm-b$top_mm,'mm'),width=unit(b$width_mm,'mm'),height=unit(3,'mm'),just=c('left','top'),gp=gpar(fill='white',col=NA));grid.text(b$tag,x=unit(b$left_mm+.5,'mm'),y=unit(wh$height_mm-b$top_mm-.4,'mm'),just=c('left','top'),gp=gpar(fontfamily='Arial',fontsize=8.5,fontface='bold'))};popViewport()
}
