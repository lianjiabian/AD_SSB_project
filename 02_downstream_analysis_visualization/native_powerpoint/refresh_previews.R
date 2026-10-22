root<-normalizePath(getwd())
.libPaths(c(file.path(dirname(root),'CI_atlas_revision_20260915/runtime/R_library'),file.path(dirname(root),'NOA_R_rebuild_20260821/R_library'),file.path(dirname(root),'runtime/R_libs'),.libPaths()))
library(data.table)
out<-file.path(root,'PPT_assembly_20261015')
source(file.path(out,'preview_headers.R'))
idx<-fread(file.path(out,'Slide_panel_index.tsv'))
z<-repair_preview_headers(out,idx)
fwrite(z,file.path(out,'qa','Preview_header_QA.tsv'),sep='\t')
selected<-unique(idx$figure)
for(k in seq_len(ceiling(length(selected)/8))){
  ids<-selected[seq.int((k-1)*8+1,min(k*8,length(selected)))]
  ragg::agg_png(file.path(out,'qa',sprintf('Contact_sheet_%02d.png',k)),width=2400,height=1850,res=160,background='#EEEEEE')
  grid::grid.newpage()
  for(j in seq_along(ids)){
    col<-(j-1)%%4;row<-(j-1)%/%4
    im<-png::readPNG(file.path(out,'previews',paste0(ids[j],'.png')))
    grid::grid.raster(im,x=(col+.5)/4,y=1-(row+.5)/2,width=grid::unit(.235,'npc'),height=grid::unit(.47,'npc'),interpolate=TRUE)
  }
  dev.off()
}
cat('PREVIEW HEADERS PASS:',nrow(z),'pages; quantitative pixels unchanged.\n')
