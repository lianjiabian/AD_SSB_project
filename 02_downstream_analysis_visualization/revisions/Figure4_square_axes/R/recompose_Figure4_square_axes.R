# Figure 4 display-only revision: two rows x four columns, with equal physical
# x/y axis lengths in every panel. Numeric units, limits, tests and data stay.
SRC<-"/inputs/ssb_study/SSB_manuscript_reorganized_20261015/final_figure_package"
PREVIOUS<-"/inputs/ssb_study/SSB_Figure4_layout_20261019"
OUT<-"/inputs/ssb_study/SSB_Figure4_square_axes_20261022"
Sys.setenv(SSB_REVISION_ROOT=SRC)
source(file.path(SRC,"R/00_common.R"))
for(d in c("figures","QA","source_data","R")) dir.create(file.path(OUT,d),recursive=TRUE,showWarnings=FALSE)
stopifnot(all(vapply(c("svglite","ragg","rvg","officer","xml2","zip","openxlsx"),
                    requireNamespace,logical(1),quietly=TRUE)))
target_mm<-60
font_size<-8.5
header_mm<-3
pad_mm<-2
reg<-readRDS(P("mapping_and_QC/figure_registry.rds"))
ids<-paste0("Fig4",LETTERS[1:8])
inputs<-c(file.path(PREVIOUS,"figures",paste0("Figure_4_layout_2x4",c(".pdf",".svg",".png",".tiff","_editable.pptx"))),
          P("main_figures/Main_figures_editable.pptx"),
          unlist(lapply(ids,function(id) {
            src_id<-reg$panels[new_id==id,old_id]
            c(P("source_panels/originals",paste0(src_id,".rds")),
              P("source_data/panels",id,"plot_data.tsv"),
              P("source_data/panels",id,"statistics.tsv"),
              P("source_data/panels",id,"participants.tsv"))
          })))
stopifnot(all(file.exists(inputs)))
before<-tools::md5sum(inputs)
plots<-setNames(vector("list",8),ids)
audits<-list()
for(k in 1:8) {
  p0<-load_panel(ids[k],font_size)
  p<-p0+theme(aspect.ratio=1)
  stopifnot(identical(p0$data,p$data),identical(p0$coordinates,p$coordinates),
            identical(lapply(p0$layers,function(z)z$data),lapply(p$layers,function(z)z$data)))
  assign("d",p$data,envir=.GlobalEnv)
  set.seed(20261022L+k);b0<-ggplot_build(p0)
  set.seed(20261022L+k);b1<-ggplot_build(p)
  stopifnot(identical(b0$data,b1$data))
  plots[[ids[k]]]<-p
  audits[[k]]<-data.table(panel=ids[k],raw_plot_data_unchanged=TRUE,
       built_layer_values_unchanged=TRUE,numeric_coordinate_system_unchanged=TRUE,
       built_rows=sum(vapply(b1$data,nrow,integer(1))))
}
fwrite(rbindlist(audits),file.path(OUT,"QA/Scientific_value_preservation.tsv"),sep="\t")

make_square_grob<-function(k) {
  p<-plots[[k]]
  assign("d",p$data,envir=.GlobalEnv)
  set.seed(20261022L+k)
  g<-ggplotGrob(p)
  idx<-which(g$layout$name=="panel")
  stopifnot(length(idx)==1L)
  box<-g$layout[idx,]
  stopifnot(box$l==box$r,box$t==box$b)
  # Fixed physical units enforce axis equality, independent of outer labels.
  g$widths[box$l]<-unit(target_mm,"mm")
  g$heights[box$t]<-unit(target_mm,"mm")
  g$respect<-FALSE
  g$name<-paste0("square_",ids[k])
  mmw<-function(u)convertWidth(sum(u),"mm",valueOnly=TRUE)
  mmh<-function(u)convertHeight(sum(u),"mm",valueOnly=TRUE)
  left<-mmw(g$widths[seq_len(box$l-1L)])
  right<-mmw(g$widths[seq.int(box$r+1L,length(g$widths))])
  top<-mmh(g$heights[seq_len(box$t-1L)])
  bottom<-mmh(g$heights[seq.int(box$b+1L,length(g$heights))])
  list(g=g,left=left,right=right,top=top,bottom=bottom,
       width=left+target_mm+right,height=top+target_mm+bottom,
       panel_width=mmw(g$widths[box$l]),panel_height=mmh(g$heights[box$t]))
}

# Measure label/legend gutters using Arial on Cairo, not a substituted font.
cairo_pdf(file.path(OUT,"QA/font_metrics.pdf"),width=366/25.4,height=220/25.4,family="Arial")
grid.newpage()
metrics<-rbindlist(lapply(1:8,function(k) {
  q<-make_square_grob(k)
  data.table(panel=ids[k],tag=LETTERS[k],row=(k-1L)%/%4L+1L,column=(k-1L)%%4L+1L,
             left=q$left,right=q$right,top=q$top,bottom=q$bottom,
             axis_x_mm=q$panel_width,axis_y_mm=q$panel_height)
}))
dev.off()
stopifnot(all(abs(metrics$axis_x_mm-target_mm)<1e-8),
          all(abs(metrics$axis_y_mm-target_mm)<1e-8))
colgut<-metrics[,.(left=max(left),right=max(right)),by=column][order(column)]
rowgut<-metrics[,.(top=max(top),bottom=max(bottom)),by=row][order(row)]
cell_width<-max(91.5,ceiling(max(colgut$left+target_mm+colgut$right)+2*pad_mm))
cell_height<-ceiling(max(rowgut$top+target_mm+rowgut$bottom)+header_mm+2*pad_mm)
width<-4*cell_width;height<-2*cell_height
lay<-metrics[,.(panel,tag,row,column,axis_x_mm,axis_y_mm)]
lay[,`:=`(left_mm=(column-1)*cell_width,top_mm=(row-1)*cell_height,
           width_mm=cell_width,height_mm=cell_height)]
fwrite(lay,file.path(OUT,"source_data/Figure4_square_axis_layout.tsv"),sep="\t")
fwrite(metrics,file.path(OUT,"QA/Measured_plot_gutters_and_axes.tsv"),sep="\t")
openxlsx::write.xlsx(list(Panel_geometry=as.data.frame(lay),
  Parameters=data.frame(parameter=c("x axis physical length (mm)","y axis physical length (mm)",
    "Figure width (mm)","Figure height (mm)","Arial font (pt)","Numeric scale changes"),
    value=c(target_mm,target_mm,width,height,font_size,"None"))),
    file.path(OUT,"source_data/Figure4_square_axis_geometry.xlsx"),overwrite=TRUE)

measure_drawn<-list()
draw_cell<-function(k,newpage=FALSE,record=FALSE) {
  if(newpage)grid.newpage()
  q<-make_square_grob(k)
  cc<-lay$column[k];rr<-lay$row[k]
  xpad<-(cell_width-(colgut$left[cc]+target_mm+colgut$right[cc]))/2
  panel_x<-xpad+colgut$left[cc]
  panel_y<-header_mm+pad_mm+rowgut$top[rr]
  x<-panel_x-q$left;y<-panel_y-q$top
  stopifnot(x>-.1,y>=header_mm-.1,x+q$width<=cell_width+.1,
            y+q$height<=cell_height+.1,
            abs(q$panel_width-q$panel_height)<1e-8)
  pushViewport(viewport(x=unit(x,"mm"),y=unit(cell_height-y,"mm"),
    width=unit(q$width,"mm"),height=unit(q$height,"mm"),
    just=c("left","top"),clip="off"))
  grid.draw(q$g);popViewport()
  grid.text(lay$tag[k],x=unit(.5,"mm"),y=unit(cell_height-.4,"mm"),
    just=c("left","top"),gp=gpar(fontfamily="Arial",fontsize=font_size,fontface="bold"))
  if(record)measure_drawn[[lay$panel[k]]]<<-data.table(panel=lay$panel[k],
      axis_x_mm=q$panel_width,axis_y_mm=q$panel_height,
      axis_difference_mm=q$panel_width-q$panel_height,
      page_panel_left_mm=lay$left_mm[k]+panel_x,
      page_panel_top_mm=lay$top_mm[k]+panel_y)
}
draw_figure<-function(record=FALSE) {
  grid.newpage()
  for(k in 1:8) {
    pushViewport(viewport(x=unit(lay$left_mm[k],"mm"),y=unit(height-lay$top_mm[k],"mm"),
      width=unit(cell_width,"mm"),height=unit(cell_height,"mm"),just=c("left","top"),clip="off"))
    draw_cell(k,record=record);upViewport(0)
  }
}
stem<-file.path(OUT,"figures/Figure_4_2x4_equal_axes")
cairo_pdf(paste0(stem,".pdf"),width=width/25.4,height=height/25.4,family="Arial")
draw_figure();dev.off()
svglite::svglite(paste0(stem,".svg"),width=width/25.4,height=height/25.4)
draw_figure(record=TRUE);dev.off()
fwrite(rbindlist(measure_drawn),file.path(OUT,"QA/Exported_axis_geometry.tsv"),sep="\t")
ragg::agg_png(paste0(stem,".png"),width=width,height=height,units="mm",res=160)
draw_figure();dev.off()
ragg::agg_tiff(paste0(stem,".tiff"),width=width,height=height,units="mm",res=600,compression="lzw")
draw_figure();dev.off()
cat("PDF/SVG/PNG/TIFF complete;",width,"x",height,"mm\n");flush.console()

# Redraw native editable DrawingML at the final physical panel geometry;
# anisotropic scaling of old slides is deliberately not used.
ns<-c(p="http://schemas.openxmlformats.org/presentationml/2006/main",
      a="http://schemas.openxmlformats.org/drawingml/2006/main",
      r="http://schemas.openxmlformats.org/officeDocument/2006/relationships")
ppt<-officer::read_pptx(P("main_figures/Main_figures_editable.pptx"))
for(i in rev(seq_len(length(ppt))))if(i!=4L)ppt<-officer::remove_slide(ppt,index=i)
skel<-file.path(OUT,"QA/PPT_skeleton.pptx");print(ppt,target=skel)
build<-tempfile("square_axes_native_");dir.create(build);unzip(skel,exdir=build)
sf<-list.files(file.path(build,"ppt/slides"),pattern="^slide[0-9]+[.]xml$",full.names=TRUE)
stopifnot(length(sf)==1L)
x<-xml2::read_xml(sf);tree<-xml2::xml_find_first(x,"/p:sld/p:cSld/p:spTree",ns)
for(k in 1:8) {
  node<-xml2::xml_find_first(x,paste0('//p:grpSp[p:nvGrpSpPr/p:cNvPr[@name="',ids[k],'"]]'),ns)
  stopifnot(!inherits(node,"xml_missing"));xml2::xml_remove(node)
  tmp<-file.path(OUT,"QA",paste0(ids[k],"_native.xml"))
  rvg::dml_pptx(file=tmp,width=cell_width/25.4,height=cell_height/25.4,
      offx=(lay$left_mm[k]+8.5)/25.4,offy=(lay$top_mm[k]+15)/25.4,
      bg="white",editable=TRUE,standalone=FALSE)
  tryCatch(draw_cell(k,newpage=TRUE),finally=dev.off())
  raw<-sub("<[?]xml[^>]*[?]>","",readLines(tmp,warn=FALSE),perl=TRUE)
  wx<-xml2::read_xml(paste0('<root xmlns:p="',ns["p"],'" xmlns:a="',ns["a"],
      '" xmlns:r="',ns["r"],'">',paste(raw,collapse=""),"</root>"))
  gp<-xml2::xml_find_first(wx,".//p:grpSp",ns)
  stopifnot(!inherits(gp,"xml_missing"))
  nn<-xml2::xml_add_child(tree,gp,.copy=TRUE)
  xml2::xml_set_attr(xml2::xml_find_first(nn,"./p:nvGrpSpPr/p:cNvPr",ns),"name",ids[k])
  cat("PPT",ids[k],"complete\n");flush.console()
}
cnv<-xml2::xml_find_all(x,"//p:cNvPr",ns)
xml2::xml_set_attr(cnv,"id",as.character(seq_along(cnv)))
xml2::write_xml(x,sf)
pf<-file.path(build,"ppt/presentation.xml");px<-xml2::read_xml(pf)
sz<-xml2::xml_find_first(px,"//p:sldSz",ns)
xml2::xml_set_attr(sz,"cx",as.character(round((width+17)*36000)))
xml2::xml_set_attr(sz,"cy",as.character(round((height+30)*36000)))
xml2::write_xml(px,pf)
groups<-xml2::xml_find_all(x,"//p:grpSp/p:nvGrpSpPr/p:cNvPr",ns)
qa_ppt<-data.table(slides=1L,editable_panel_groups=length(groups),
  raster_pictures=length(xml2::xml_find_all(x,"//p:pic",ns)),
  native_shapes=length(xml2::xml_find_all(x,"//p:sp",ns)),
  editable_text_runs=length(xml2::xml_find_all(x,"//a:t",ns)),
  duplicate_ids=anyDuplicated(xml2::xml_attr(cnv,"id")))
stopifnot(qa_ppt$editable_panel_groups==8L,qa_ppt$raster_pictures==0L,
          qa_ppt$duplicate_ids==0L,setequal(xml2::xml_attr(groups,"name"),ids))
zip::zipr(paste0(stem,"_editable.pptx"),files=list.files(build,all.files=TRUE,no..=TRUE),root=build)
fwrite(qa_ppt,file.path(OUT,"QA/PowerPoint_structure_QA.tsv"),sep="\t")
stopifnot(identical(before,tools::md5sum(inputs)))
fwrite(data.table(file=inputs,md5=unname(before)),file.path(OUT,"QA/Unchanged_inputs.tsv"),sep="\t")
writeLines(c("# Figure 4: two rows, four columns, equal physical axes", "",
  sprintf("Each of A–H has a %.1f × %.1f mm plotting panel, so the x and y axis lines have equal physical length.",target_mm,target_mm),
  sprintf("Figure size: %.1f × %.1f mm. Arial %.1f pt. A–D above E–H.",width,height,font_size),
  "Square refers to the data plotting area, excluding axis labels, titles and legends.",
  "Numeric axis units, coordinate limits, data, statistical tests, P values, intervals, colours and panel numbering are unchanged.",
  "For the clinical heatmap, the complete plotting panel is square; individual cells need not be square.",
  "No models, inference, normalization, correlations or bootstraps were rerun.",
  "All eight panels were redrawn in R at the required geometry to preserve fonts, marker size and stroke width.",
  "PDF/SVG are editable vectors; PPT contains eight native editable groups; TIFF is 600 dpi and lossless.",
  "The previous October 19 figure and all original inputs remain unchanged.",
  "Geometry measurements, data-preservation checks and input checksums are in QA/.",
  "Run R/recompose_Figure4_square_axes.R in the project R environment to reproduce."),file.path(OUT,"README.md"))
writeLines(capture.output(sessionInfo()),file.path(OUT,"QA/sessionInfo.txt"))
writeLines(capture.output(warnings()),file.path(OUT,"QA/R_warnings.txt"))
graphics.off()
cat("PASS: eight square plotting panels, axes",target_mm,"mm; all scientific layer values unchanged.\n")
