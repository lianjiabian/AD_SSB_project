# Presentation-only Figure 4 assembly: A–D above E–H.
# Keep the original 91.5 x 62.5 mm panels, fonts, marks and statistical results.
SRC<-"/inputs/ssb_study/SSB_manuscript_reorganized_20261015/final_figure_package"
OUT<-"/inputs/ssb_study/SSB_Figure4_layout_20261019"
Sys.setenv(SSB_REVISION_ROOT=SRC)
source(file.path(SRC,"R/00_common.R"))
for(d in c("figures","QA","source_data","R")) dir.create(file.path(OUT,d),recursive=TRUE,showWarnings=FALSE)
options(device=function(...) grDevices::cairo_pdf(filename=file.path(OUT,"QA/font_metrics.pdf"),
  width=366/25.4,height=125/25.4,family="Arial",...))
stopifnot(all(vapply(c("svglite","ragg","officer","xml2","zip","openxlsx"),
                    requireNamespace,logical(1),quietly=TRUE)))
reg<-readRDS(P("mapping_and_QC/figure_registry.rds"))
old<-copy(reg$layouts$Figure4)
lay<-copy(old)
lay[,`:=`(row=rep(1:2,each=4),column=rep(1:4,2))]
lay[,`:=`(left_mm=(column-1)*91.5,top_mm=(row-1)*62.5)]
width<-366;height<-125
stopifnot(identical(lay$width_mm,old$width_mm),identical(lay$height_mm,old$height_mm),
          identical(lay$tag,LETTERS[1:8]),all(table(lay$row)==4L))
fwrite(lay,file.path(OUT,"source_data/Figure4_layout.tsv"),sep="\t")
openxlsx::write.xlsx(list(New_layout=as.data.frame(lay),Original_layout=as.data.frame(old)),
                    file.path(OUT,"source_data/Figure4_layout.xlsx"),overwrite=TRUE)
inputs<-c(P("main_figures",paste0("Figure_4.",c("pdf","svg","png","tiff"))),
          P("main_figures/Main_figures_editable.pptx"),
          unlist(lapply(lay$new_id,function(id) {
            src_id<-reg$panels[new_id==id,old_id]
            c(P("source_panels/originals",paste0(src_id,".rds")),
              P("source_data/panels",id,"plot_data.tsv"),
              P("source_data/panels",id,"statistics.tsv"),
              P("source_data/panels",id,"participants.tsv"))
          })))
stopifnot(all(file.exists(inputs)))
hash_before<-tools::md5sum(inputs)
plots<-setNames(lapply(lay$new_id,load_panel,size=8.5),lay$new_id)
audit<-rbindlist(lapply(lay$new_id,function(id) {
  p<-plots[[id]];assign("d",p$data,envir=.GlobalEnv)
  b<-ggplot_build(p)
  data.table(panel=id,plot_rows=nrow(p$data),built_layer_rows=sum(vapply(b$data,nrow,integer(1))),
    panel_content_modified=FALSE,statistical_reanalysis=FALSE)
}))
fwrite(audit,file.path(OUT,"QA/Scientific_content_audit.tsv"),sep="\t")
draw_new<-function() {
  grid.newpage()
  for(i in 1:8) {
    b<-lay[i]
    pushViewport(viewport(x=unit(b$left_mm,"mm"),y=unit(height-b$top_mm,"mm"),
      width=unit(b$width_mm,"mm"),height=unit(b$height_mm,"mm"),just=c("left","top")))
    draw_panel(plots[[b$new_id]],b$tag,newpage=FALSE)
    upViewport(0)
  }
  pushViewport(viewport(clip="off"))
  for(i in 1:8) {
    b<-lay[i]
    grid.rect(x=unit(b$left_mm,"mm"),y=unit(height-b$top_mm,"mm"),
      width=unit(b$width_mm,"mm"),height=unit(3,"mm"),just=c("left","top"),
      gp=gpar(fill="white",col=NA))
    grid.text(b$tag,x=unit(b$left_mm+.5,"mm"),y=unit(height-b$top_mm-.4,"mm"),
      just=c("left","top"),gp=gpar(fontfamily="Arial",fontsize=8.5,fontface="bold"))
  }
  popViewport()
}
stem<-file.path(OUT,"figures/Figure_4_layout_2x4")
cairo_pdf(paste0(stem,".pdf"),width=width/25.4,height=height/25.4,family="Arial")
draw_new();dev.off()
svglite::svglite(paste0(stem,".svg"),width=width/25.4,height=height/25.4)
draw_new();dev.off()
ragg::agg_png(paste0(stem,".png"),width=width,height=height,units="mm",res=160)
draw_new();dev.off()
ragg::agg_tiff(paste0(stem,".tiff"),width=width,height=height,units="mm",res=600,compression="lzw")
draw_new();dev.off()
cat("PDF/SVG/PNG/TIFF complete\n");flush.console()

# Native PowerPoint: preserve all eight original vector groups and translate
# their group origins. No scientific point, line, text or glyph is recreated.
ns<-c(p="http://schemas.openxmlformats.org/presentationml/2006/main",
      a="http://schemas.openxmlformats.org/drawingml/2006/main")
deck<-officer::read_pptx(P("main_figures/Main_figures_editable.pptx"))
for(i in rev(seq_len(length(deck)))) if(i!=4L) deck<-officer::remove_slide(deck,index=i)
skel<-file.path(OUT,"QA/PPT_skeleton.pptx");print(deck,target=skel)
build<-tempfile("figure4_native_");dir.create(build);unzip(skel,exdir=build)
sf<-list.files(file.path(build,"ppt/slides"),pattern="^slide[0-9]+[.]xml$",full.names=TRUE)
stopifnot(length(sf)==1L)
x<-xml2::read_xml(sf)
lineage<-list()
for(i in 1:8) {
  id<-lay$new_id[i]
  node<-xml2::xml_find_first(x,paste0('//p:grpSp[p:nvGrpSpPr/p:cNvPr[@name="',id,'"]]'),ns)
  stopifnot(!inherits(node,"xml_missing"))
  paths_before<-vapply(xml2::xml_find_all(node,".//a:pathLst",ns),as.character,character(1))
  texts_before<-vapply(xml2::xml_find_all(node,".//a:r",ns),as.character,character(1))
  extent_before<-as.character(xml2::xml_find_first(node,"./p:grpSpPr/a:xfrm/a:ext",ns))
  offset<-xml2::xml_find_first(node,"./p:grpSpPr/a:xfrm/a:off",ns)
  xml2::xml_set_attr(offset,"x",as.character(round((lay$left_mm[i]+8.5)*36000)))
  xml2::xml_set_attr(offset,"y",as.character(round((lay$top_mm[i]+15)*36000)))
  ok<-identical(paths_before,vapply(xml2::xml_find_all(node,".//a:pathLst",ns),as.character,character(1)))&&
      identical(texts_before,vapply(xml2::xml_find_all(node,".//a:r",ns),as.character,character(1)))&&
      identical(extent_before,as.character(xml2::xml_find_first(node,"./p:grpSpPr/a:xfrm/a:ext",ns)))
  stopifnot(ok)
  lineage[[id]]<-data.table(panel=id,mode="Original native vector group; translation only",
    geometry_text_fonts_and_dimensions_unchanged=ok)
}
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
  editable_text_runs=length(xml2::xml_find_all(x,"//a:t",ns)))
stopifnot(qa_ppt$editable_panel_groups==8L,qa_ppt$raster_pictures==0L,
          setequal(xml2::xml_attr(groups,"name"),lay$new_id))
zip::zipr(paste0(stem,"_editable.pptx"),files=list.files(build,all.files=TRUE,no..=TRUE),root=build)
fwrite(qa_ppt,file.path(OUT,"QA/PowerPoint_structure_QA.tsv"),sep="\t")
fwrite(rbindlist(lineage),file.path(OUT,"QA/PowerPoint_vector_preservation.tsv"),sep="\t")
stopifnot(identical(hash_before,tools::md5sum(inputs)))
fwrite(data.table(file=inputs,md5=unname(hash_before)),file.path(OUT,"QA/Unchanged_source_checksums.tsv"),sep="\t")
svg<-readLines(paste0(stem,".svg"),warn=FALSE)
stopifnot(!any(grepl("<image",svg,fixed=TRUE)))
writeLines(c("# Figure 4 — two rows, four columns", "",
  "Top row: A, B, C, D. Bottom row: E, F, G, H.",
  "Each panel retains its original physical dimensions, 91.5 × 62.5 mm, and its original 8.5-pt Arial typography.",
  "The wide assembly is 366 × 125 mm; no panel has been reduced to an unreadably small thumbnail.",
  "All colours, axes, clinical sample sizes, predictions, P values, curves, estimates and intervals are unchanged.",
  "No statistical analyses, normalization, models or clinical correlations were rerun.",
  "PowerPoint preserves the eight original native editable vector groups, with translation only.",
  "PDF/SVG remain vector files. TIFF is lossless at 600 dpi. Original project files were not overwritten.",
  "Figure 4 panel numbering and legend wording remain unchanged.",
  "R/recompose_Figure4.R reproduces this assembly from the original approved panel objects."),file.path(OUT,"README.md"))
writeLines(capture.output(sessionInfo()),file.path(OUT,"QA/sessionInfo.txt"))
writeLines(capture.output(warnings()),file.path(OUT,"QA/R_warnings.txt"))
graphics.off()
cat("PASS: Figure 4 two rows x four columns; original panel dimensions and all scientific content preserved.\n")
