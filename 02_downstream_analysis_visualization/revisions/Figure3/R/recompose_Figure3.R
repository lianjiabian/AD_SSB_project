# Figure 3 layout-only revision. Retain the original A-row height, put A/B
# in a 2:1 row, remove the old separate B row, and translate C–F upwards.
SRC<-"/inputs/ssb_study/SSB_manuscript_reorganized_20261015/final_figure_package"
OUT<-"/inputs/ssb_study/SSB_Figure3_layout_20261019"
Sys.setenv(SSB_REVISION_ROOT=SRC)
source(file.path(SRC,"R/00_common.R"))
for(d in c("figures","QA","source_data","R")) dir.create(file.path(OUT,d),recursive=TRUE,showWarnings=FALSE)
options(device=function(...) grDevices::cairo_pdf(filename=file.path(OUT,"QA/font_metrics.pdf"),
       width=183/25.4,height=250/25.4,family="Arial",...))
stopifnot(all(vapply(c("svglite","ragg","rvg","officer","xml2","zip","openxlsx"),
                    requireNamespace,logical(1),quietly=TRUE)))
reg<-readRDS(P("mapping_and_QC/figure_registry.rds"))
old<-copy(reg$layouts$Figure3);lay<-copy(old)
removed_height<-old[new_id=="Fig3B",height_mm]
height<-250-removed_height
lay[new_id=="Fig3A",width_mm:=122]
lay[new_id=="Fig3B",`:=`(left_mm=122,top_mm=0,width_mm=61,
                         height_mm=old[new_id=="Fig3A",height_mm])]
lay[new_id%in%paste0("Fig3",LETTERS[3:6]),top_mm:=top_mm-removed_height]
stopifnot(lay[new_id=="Fig3A",height_mm]==old[new_id=="Fig3A",height_mm],
          lay[new_id=="Fig3B",height_mm]==old[new_id=="Fig3A",height_mm],
          lay[new_id=="Fig3A",width_mm]/lay[new_id=="Fig3B",width_mm]==2,
          identical(lay[3:6,.(left_mm,width_mm,height_mm)],old[3:6,.(left_mm,width_mm,height_mm)]))
fwrite(lay,file.path(OUT,"source_data/Figure3_layout.tsv"),sep="\t")
openxlsx::write.xlsx(list(New_layout=as.data.frame(lay),Original_layout=as.data.frame(old)),
                    file.path(OUT,"source_data/Figure3_layout.xlsx"),overwrite=TRUE)
inputs<-c(P("main_figures",paste0("Figure_3.",c("pdf","svg","png","tiff"))),
          P("main_figures/Main_figures_editable.pptx"),
          unlist(lapply(lay$new_id,function(id)c(P("source_panels/originals",paste0(id,".rds")),
               P("source_data/panels",id,"plot_data.tsv"),
               P("source_data/panels",id,"statistics.tsv"),
               P("source_data/panels",id,"participants.tsv")))))
stopifnot(all(file.exists(inputs)))
hash_before<-tools::md5sum(inputs)
plots<-setNames(lapply(lay$new_id,load_panel,size=8.5),lay$new_id)
audit<-rbindlist(lapply(lay$new_id,function(id) {
  p<-plots[[id]];assign("d",p$data,envir=.GlobalEnv)
  built<-ggplot_build(p)
  data.table(panel=id,data_rows=nrow(p$data),built_layer_rows=sum(vapply(built$data,nrow,integer(1))),
             scientific_plot_object_changed=FALSE,statistical_reanalysis=FALSE)
}))
fwrite(audit,file.path(OUT,"QA/Scientific_content_audit.tsv"),sep="\t")
draw_new<-function() {
  grid.newpage()
  for(i in 1:6) {
    b<-lay[i]
    pushViewport(viewport(x=unit(b$left_mm,"mm"),y=unit(height-b$top_mm,"mm"),
      width=unit(b$width_mm,"mm"),height=unit(b$height_mm,"mm"),just=c("left","top")))
    draw_panel(plots[[b$new_id]],b$tag,newpage=FALSE)
    upViewport(0)
  }
  pushViewport(viewport(clip="off"))
  for(i in 1:6) {
    b<-lay[i]
    grid.rect(x=unit(b$left_mm,"mm"),y=unit(height-b$top_mm,"mm"),
      width=unit(b$width_mm,"mm"),height=unit(3,"mm"),just=c("left","top"),
      gp=gpar(fill="white",col=NA))
    grid.text(b$tag,x=unit(b$left_mm+.5,"mm"),y=unit(height-b$top_mm-.4,"mm"),
      just=c("left","top"),gp=gpar(fontfamily="Arial",fontsize=8.5,fontface="bold"))
  }
  popViewport()
}
stem<-file.path(OUT,"figures/Figure_3_layout_AB_2to1")
if(Sys.getenv("SSB_FIG3_PPT_ONLY")!="1") {
cairo_pdf(paste0(stem,".pdf"),width=183/25.4,height=height/25.4,family="Arial")
draw_new();dev.off()
svglite::svglite(paste0(stem,".svg"),width=183/25.4,height=height/25.4)
draw_new();dev.off()
ragg::agg_png(paste0(stem,".png"),width=183,height=height,units="mm",res=160)
draw_new();dev.off()
ragg::agg_tiff(paste0(stem,".tiff"),width=183,height=height,units="mm",res=600,compression="lzw")
draw_new();dev.off()
cat("PDF/SVG/PNG/TIFF complete\n");flush.console()
}

# Preserve C–F as original native PowerPoint groups, changing only their
# vertical translations. A/B are rendered at the requested new dimensions.
ns<-c(p="http://schemas.openxmlformats.org/presentationml/2006/main",
      a="http://schemas.openxmlformats.org/drawingml/2006/main",
      r="http://schemas.openxmlformats.org/officeDocument/2006/relationships")
deck<-officer::read_pptx(P("main_figures/Main_figures_editable.pptx"))
for(i in rev(seq_len(length(deck)))) if(i!=3L) deck<-officer::remove_slide(deck,index=i)
skel<-file.path(OUT,"QA/PPT_skeleton.pptx");print(deck,target=skel)
build<-tempfile("figure3_native_");dir.create(build);unzip(skel,exdir=build)
sf<-list.files(file.path(build,"ppt/slides"),pattern="^slide[0-9]+[.]xml$",full.names=TRUE)
stopifnot(length(sf)==1L)
x<-xml2::read_xml(sf)
tree<-xml2::xml_find_first(x,"/p:sld/p:cSld/p:spTree",ns)
preserved<-list()
for(id in paste0("Fig3",LETTERS[3:6])) {
  node<-xml2::xml_find_first(x,paste0('//p:grpSp[p:nvGrpSpPr/p:cNvPr[@name="',id,'"]]'),ns)
  stopifnot(!inherits(node,"xml_missing"))
  paths_before<-vapply(xml2::xml_find_all(node,".//a:pathLst",ns),as.character,character(1))
  fonts_before<-xml2::xml_attr(xml2::xml_find_all(node,".//a:rPr",ns),"sz")
  texts_before<-xml2::xml_text(xml2::xml_find_all(node,".//a:t",ns))
  off<-xml2::xml_find_first(node,"./p:grpSpPr/a:xfrm/a:off",ns)
  old_y<-as.numeric(xml2::xml_attr(off,"y"))
  xml2::xml_set_attr(off,"y",as.character(round(old_y-removed_height*36000)))
  ok<-identical(paths_before,vapply(xml2::xml_find_all(node,".//a:pathLst",ns),as.character,character(1)))&&
      identical(fonts_before,xml2::xml_attr(xml2::xml_find_all(node,".//a:rPr",ns),"sz"))&&
      identical(texts_before,xml2::xml_text(xml2::xml_find_all(node,".//a:t",ns)))
  stopifnot(ok)
  preserved[[id]]<-data.table(panel=id,mode="Original native vector group; vertical translation only",
          local_geometry_fonts_and_text_unchanged=ok)
}
for(id in c("Fig3A","Fig3B")) {
  node<-xml2::xml_find_first(x,paste0('//p:grpSp[p:nvGrpSpPr/p:cNvPr[@name="',id,'"]]'),ns)
  stopifnot(!inherits(node,"xml_missing"));xml2::xml_remove(node)
  b<-lay[new_id==id];tmp<-file.path(OUT,"QA",paste0(id,"_native.xml"))
  rvg::dml_pptx(file=tmp,width=b$width_mm/25.4,height=b$height_mm/25.4,
     offx=(b$left_mm+8.5)/25.4,offy=(b$top_mm+15)/25.4,
     bg="white",editable=TRUE,standalone=FALSE)
  tryCatch(draw_panel(plots[[id]],b$tag),finally=dev.off())
  raw<-sub("<[?]xml[^>]*[?]>","",readLines(tmp,warn=FALSE),perl=TRUE)
  wrap<-paste0('<root xmlns:p="',ns["p"],'" xmlns:a="',ns["a"],'" xmlns:r="',ns["r"],'">',
                paste(raw,collapse=""),"</root>")
  wx<-xml2::read_xml(wrap);gp<-xml2::xml_find_first(wx,".//p:grpSp",ns)
  node<-xml2::xml_add_child(tree,gp,.copy=TRUE)
  xml2::xml_set_attr(xml2::xml_find_first(node,"./p:nvGrpSpPr/p:cNvPr",ns),"name",id)
}
ids<-xml2::xml_find_all(x,"//p:cNvPr",ns)
xml2::xml_set_attr(ids,"id",as.character(seq_along(ids)))
xml2::write_xml(x,sf)
presentation<-file.path(build,"ppt/presentation.xml")
px<-xml2::read_xml(presentation)
sz<-xml2::xml_find_first(px,"//p:sldSz",ns)
xml2::xml_set_attr(sz,"cy",as.character(round((height+30)*36000)))
xml2::write_xml(px,presentation)
groupnames<-xml2::xml_attr(xml2::xml_find_all(x,"//p:grpSp/p:nvGrpSpPr/p:cNvPr",ns),"name")
stopifnot(setequal(groupnames,lay$new_id),length(groupnames)==6L,
          length(xml2::xml_find_all(x,"//p:pic",ns))==0L)
zip::zipr(paste0(stem,"_editable.pptx"),files=list.files(build,all.files=TRUE,no..=TRUE),root=build)
fwrite(rbindlist(preserved),file.path(OUT,"QA/PowerPoint_CF_preservation.tsv"),sep="\t")
stopifnot(identical(hash_before,tools::md5sum(inputs)))
fwrite(data.table(file=inputs,md5=unname(hash_before)),file.path(OUT,"QA/Unchanged_source_checksums.tsv"),sep="\t")
svg<-readLines(paste0(stem,".svg"),warn=FALSE)
stopifnot(!any(grepl("<image",svg,fixed=TRUE)))
writeLines(c("# Figure 3: A/B side by side, width ratio 2:1", "",
  sprintf("Figure: 183 × %.6f mm. New A/B row: %.6f mm high, the original A-row height.",height,lay$height_mm[1]),
  sprintf("A is 122 mm wide; B is 61 mm wide. The former %.6f-mm B row is removed.",removed_height),
  "C–F move upwards by exactly the removed row height. Their dimensions, relative layout and content stay unchanged.",
  "All panel labels, scientific results, colours, fonts and line widths are unchanged.",
  "No count, normalization, model, enrichment, bootstrap or statistical test was rerun.",
  "The original files are preserved. Vector PDF/SVG, native editable PPT and 600-dpi TIFF are in figures/.",
  "C–F in PowerPoint reuse their original native vector groups with translation only.",
  "The existing Figure 3 legend remains valid because panel numbering and contents have not changed."),file.path(OUT,"README.md"))
writeLines(capture.output(sessionInfo()),file.path(OUT,"QA/sessionInfo.txt"))
writeLines(capture.output(warnings()),file.path(OUT,"QA/R_warnings.txt"))
graphics.off()
cat("PASS: Figure 3 A/B 2:1; original A-row height; original B row removed; C–F preserved.\n")
