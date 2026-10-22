# Figure 2: presentation-only reflow of the ten approved R panel objects.
# No input matrix, model, comparison, P value, feature list or participant changes.
SRC <- "/inputs/ssb_study/SSB_manuscript_reorganized_20261015/final_figure_package"
OUT <- "/inputs/ssb_study/SSB_Figure2_layout_20261019"
# Measure Arial on the same Cairo backend used for the vector export.
# The temporary metric device stays within this revision's QA directory.
options(device=function(...) grDevices::cairo_pdf(
  filename=file.path(OUT,"QA/font_metrics.pdf"),width=183/25.4,height=225/25.4,
  family="Arial",...))
Sys.setenv(SSB_REVISION_ROOT=SRC)
source(file.path(SRC,"R/00_common.R"))
stopifnot(all(vapply(c("svglite","ragg","rvg","officer","xml2","zip"),
                    requireNamespace,logical(1),quietly=TRUE)))
for(d in c("figures","R","QA","legend","source_data"))
  dir.create(file.path(OUT,d),recursive=TRUE,showWarnings=FALSE)
ids <- c(paste0("Fig2",LETTERS[1:4]),paste0("Fig2E",1:3),paste0("Fig2",LETTERS[6:8]))
oldtags <- c(LETTERS[1:4],paste0("E",1:3),LETTERS[6:8])
newtags <- LETTERS[1:10]
layout <- data.table(new_panel=paste0("Fig2",newtags),old_panel=ids,
                    old_tag=oldtags,new_tag=newtags,row=c(rep(1L,4),rep(2L,3),rep(3L,3)),
                    column=c(1:4,1:3,1:3))
layout[,width_mm:=ifelse(row==1L,183/4,183/3)]
layout[,height_mm:=75]
layout[,left_mm:=(column-1)*width_mm]
layout[,top_mm:=(row-1)*75]
fwrite(layout,file.path(OUT,"source_data/Panel_numbering_and_layout.tsv"),sep="\t")
openxlsx::write.xlsx(list(Panel_mapping=as.data.frame(layout),
  Notes=data.frame(item=c("Purpose","Scientific analysis","Source-data interpretation"),
    value=c("Layout only: four, three and three panels in rows 1, 2 and 3",
            "Unchanged; no statistical analyses rerun",
            "Original E1/E2/E3 are now E/F/G; original F/G/H are now H/I/J"))),
  file.path(OUT,"source_data/Panel_numbering_and_layout.xlsx"),overwrite=TRUE)
sourcefiles <- unlist(lapply(ids,function(id) {
  r <- readRDS(P("mapping_and_QC/figure_registry.rds"))$panels[new_id==id]
  c(P("source_panels/originals",paste0(r$old_id,".rds")),
    P("source_data/panels",id,"plot_data.tsv"),
    P("source_data/panels",id,"statistics.tsv"),
    P("source_data/panels",id,"participants.tsv"))
}))
stopifnot(all(file.exists(sourcefiles)))
hash_before <- tools::md5sum(sourcefiles)
g <- vector("list",10); plots <- vector("list",10)
layer_audit <- vector("list",10)
for(k in 1:10) {
  p0 <- load_panel(ids[k],8.5)
  p <- p0
  if(k<=4) {
    sub <- p$labels$subtitle
    sub <- sub("; lower ","\nLower ",sub,fixed=TRUE)
    p <- p+labs(x="Adjusted log2\nsignal difference",subtitle=sub)
  }
  if(k==8L) {
    p <- p+scale_y_discrete(labels=function(x) {
      x[x=="Shared, same direction"] <- "Shared,\nsame direction"
      x[x=="Direct pathology contrast"] <- "Direct pathology\ncontrast"
      x
    })
  }
  if(k==10L) p <- p+labs(subtitle="EXON associations\nagainst HC")+
      guides(colour=guide_legend(ncol=1,nrow=3,byrow=TRUE))+
      theme(legend.box.margin=margin(0,0,0,0),legend.margin=margin(0,0,0,0),
            legend.key.height=unit(3.5,"mm"))
  stopifnot(identical(p0$data,p$data),length(p0$layers)==length(p$layers),
            identical(lapply(p0$layers,function(x)x$data),lapply(p$layers,function(x)x$data)))
  assign("d",p$data,envir=.GlobalEnv)
  b0 <- ggplot_build(p0); b1 <- ggplot_build(p)
  stopifnot(identical(b0$data,b1$data))
  layer_audit[[k]] <- data.table(panel=newtags[k],
      unchanged_input_data=TRUE,unchanged_built_layer_values=TRUE,
      built_layer_rows=sum(vapply(b1$data,nrow,integer(1))))
  g[[k]] <- ggplotGrob(p)
  plots[[k]] <- p
  cat("PREPARED",newtags[k],"from",oldtags[k],"\n");flush.console()
}
names(g) <- names(plots) <- newtags
fwrite(rbindlist(layer_audit),file.path(OUT,"QA/Scientific_value_preservation.tsv"),sep="\t")
draw_cell <- function(k,newpage=FALSE) {
  if(newpage) grid.newpage()
  pushViewport(viewport(x=0,y=0,width=1,height=unit(1,"npc")-unit(3,"mm"),
                        just=c("left","bottom")))
  # Recreate only the display grob on the active export device so text-unit
  # metrics are not cached across Cairo, SVG, raster and DrawingML devices.
  assign("d",plots[[k]]$data,envir=.GlobalEnv)
  grid.draw(ggplotGrob(plots[[k]]));popViewport()
  grid.text(newtags[k],x=unit(.5,"mm"),y=unit(1,"npc")-unit(.4,"mm"),
    just=c("left","top"),gp=gpar(fontfamily="Arial",fontsize=8.5,fontface="bold"))
}
draw_figure <- function() {
  grid.newpage()
  for(k in 1:10) {
    b <- layout[k]
    pushViewport(viewport(x=unit(b$left_mm,"mm"),y=unit(225-b$top_mm,"mm"),
      width=unit(b$width_mm,"mm"),height=unit(b$height_mm,"mm"),just=c("left","top")))
    draw_cell(k);upViewport(0)
  }
  # Keep panel letters on top of all neighbouring plot backgrounds.
  pushViewport(viewport(clip="off"))
  for(k in 1:10) {
    b<-layout[k]
    grid.rect(x=unit(b$left_mm,"mm"),y=unit(225-b$top_mm,"mm"),
      width=unit(b$width_mm,"mm"),height=unit(3,"mm"),just=c("left","top"),
      gp=gpar(fill="white",col=NA))
    grid.text(newtags[k],x=unit(b$left_mm+.5,"mm"),y=unit(225-b$top_mm-.4,"mm"),
      just=c("left","top"),gp=gpar(fontfamily="Arial",fontsize=8.5,fontface="bold"))
  }
  popViewport()
}
stem <- file.path(OUT,"figures/Figure_2_layout_4-3-3")
grDevices::cairo_pdf(paste0(stem,".pdf"),width=183/25.4,height=225/25.4,family="Arial")
draw_figure();dev.off();cat("PDF complete\n");flush.console()
svglite::svglite(paste0(stem,".svg"),width=183/25.4,height=225/25.4)
draw_figure();dev.off();cat("SVG complete\n");flush.console()
ragg::agg_png(paste0(stem,".png"),width=183,height=225,units="mm",res=160)
draw_figure();dev.off();cat("PNG complete\n");flush.console()
ragg::agg_tiff(paste0(stem,".tiff"),width=183,height=225,units="mm",res=600,compression="lzw")
draw_figure();dev.off();cat("TIFF complete\n");flush.console()

# Mechanical legend renumbering: all scientific wording and numerical values stay.
leg <- readRDS(P("mapping_and_QC/legends.rds"))$main$Figure2
leg <- sub("**E1-E3**","**E-G**",leg,fixed=TRUE)
leg <- sub("**F**","**H**",leg,fixed=TRUE)
leg <- sub("**G**","**I**",leg,fixed=TRUE)
leg <- sub("**H**, EXON effects","**J**, EXON effects",leg,fixed=TRUE)
writeLines(leg,file.path(OUT,"legend/Figure_2_legend_EN.md"))
doc<-officer::read_docx()
doc<-officer::body_add_par(doc,"Figure 2 legend — revised panel numbering",style="heading 1")
doc<-officer::body_add_par(doc,gsub("**","",leg,fixed=TRUE))
print(doc,target=file.path(OUT,"legend/Figure_2_legend_EN.docx"))

# Native editable PowerPoint: each panel is an independent DrawingML group.
ns<-c(p="http://schemas.openxmlformats.org/presentationml/2006/main",
      a="http://schemas.openxmlformats.org/drawingml/2006/main",
      r="http://schemas.openxmlformats.org/officeDocument/2006/relationships")
template<-P("source_panels/portrait_template.pptx")
ppt<-officer::read_pptx(template)
while(length(ppt)) ppt<-officer::remove_slide(ppt,index=length(ppt))
ppt<-officer::add_slide(ppt,layout="Blank",master="Office Theme")
ppt<-officer::ph_with(ppt,officer::fpar(officer::ftext("Figure 2",
      officer::fp_text(font.family="Arial",font.size=12,bold=TRUE))),
      location=officer::ph_location(left=8.5/25.4,top=3/25.4,width=183/25.4,height=8/25.4))
ppt<-officer::set_notes(ppt,value=gsub("**","",leg,fixed=TRUE),
      location=officer::notes_location_type(type="body"))
skel<-file.path(OUT,"QA/PPT_skeleton.pptx");print(ppt,target=skel)
build<-tempfile("fig2_ppt_");dir.create(build);unzip(skel,exdir=build)
slide<-file.path(build,"ppt/slides/slide1.xml")
x<-xml2::read_xml(slide)
tree<-xml2::xml_find_first(x,"/p:sld/p:cSld/p:spTree",ns)
for(k in 1:10) {
  b<-layout[k];tmp<-file.path(OUT,"QA",paste0("native_panel_",newtags[k],".xml"))
  rvg::dml_pptx(file=tmp,width=b$width_mm/25.4,height=b$height_mm/25.4,
    offx=(b$left_mm+8.5)/25.4,offy=(b$top_mm+15)/25.4,
    bg="white",editable=TRUE,standalone=FALSE)
  tryCatch(draw_cell(k,newpage=TRUE),finally=dev.off())
  raw<-readLines(tmp,warn=FALSE)
  raw<-sub("<[?]xml[^>]*[?]>","",raw,perl=TRUE)
  wrap<-paste0('<root xmlns:p="',ns["p"],'" xmlns:a="',ns["a"],
               '" xmlns:r="',ns["r"],'">',paste(raw,collapse=""),"</root>")
  wx<-xml2::read_xml(wrap)
  gp<-xml2::xml_find_first(wx,".//p:grpSp",ns)
  stopifnot(!inherits(gp,"xml_missing"))
  node<-xml2::xml_add_child(tree,gp,.copy=TRUE)
  xml2::xml_set_attr(xml2::xml_find_first(node,"./p:nvGrpSpPr/p:cNvPr",ns),"name",paste0("Fig2",newtags[k]))
  cat("PPT panel",newtags[k],"complete\n");flush.console()
  rm(wx,gp,node,raw,wrap);gc(verbose=FALSE)
}
cnv<-xml2::xml_find_all(x,"//p:cNvPr",ns)
xml2::xml_set_attr(cnv,"id",as.character(seq_along(cnv)))
xml2::write_xml(x,slide)
groups<-xml2::xml_find_all(x,"//p:grpSp/p:nvGrpSpPr/p:cNvPr",ns)
qa_ppt<-data.table(slides=1L,editable_panel_groups=length(groups),
      native_shapes=length(xml2::xml_find_all(x,"//p:sp",ns)),
      raster_pictures=length(xml2::xml_find_all(x,"//p:pic",ns)),
      editable_text_runs=length(xml2::xml_find_all(x,"//a:t",ns)),
      duplicate_shape_ids=anyDuplicated(xml2::xml_attr(cnv,"id")))
stopifnot(qa_ppt$editable_panel_groups==10L,qa_ppt$raster_pictures==0L,
          qa_ppt$duplicate_shape_ids==0L,setequal(xml2::xml_attr(groups,"name"),paste0("Fig2",newtags)))
fwrite(qa_ppt,file.path(OUT,"QA/PowerPoint_structure_QA.tsv"),sep="\t")
zip::zipr(paste0(stem,"_editable.pptx"),files=list.files(build,all.files=TRUE,no..=TRUE),root=build)
stopifnot(identical(hash_before,tools::md5sum(sourcefiles)))
fwrite(data.table(file=sourcefiles,md5=unname(hash_before)),
       file.path(OUT,"QA/Unchanged_source_file_checksums.tsv"),sep="\t")
svg<-readLines(paste0(stem,".svg"),warn=FALSE)
stopifnot(!any(grepl("<image",svg,fixed=TRUE)))
writeLines(c(
  "# Figure 2 — 4 / 3 / 3 layout", "",
  "Row 1: A, B, C, D. Row 2: E, F, G. Row 3: H, I, J.",
  "Original E1/E2/E3 are now E/F/G. Original F/G/H are now H/I/J.",
  "The ten scientific panels, data, statistical results and colours are unchanged.",
  "Only panel locations, panel letters and necessary text line wrapping change.",
  "Figure size: 183 × 225 mm. Arial 8.5 pt. Vector PDF/SVG; 600-dpi TIFF.",
  "PowerPoint has ten native editable panel groups and no raster panel pictures.",
  "The English Figure 2 legend is renumbered in legend/; use this legend with the revised figure.",
  "The original manuscript, individual panels, source data and original figure files were not overwritten.",
  "R/recompose_Figure2.R reproduces the layout from the approved project panel objects.",
  "source_data/Panel_numbering_and_layout.xlsx records the old-to-new panel mapping.",
  "QA/ contains layer-value preservation tests and original source checksums."),file.path(OUT,"README.md"))
writeLines(capture.output(sessionInfo()),file.path(OUT,"QA/sessionInfo.txt"))
writeLines(capture.output(warnings()),file.path(OUT,"QA/R_warnings.txt"))
graphics.off()
cat("PASS: 4/3/3 layout; original scientific layer values and all source files unchanged.\n")
