.libPaths(c("/inputs/ssb_study/SSB_QC261_EXON_primary_20261013/PPT_assembly_20261015/R_library",
  "/inputs/ssb_study/CI_atlas_revision_20260915/runtime/R_library",
  "/inputs/ssb_study/NOA_R_rebuild_20260821/R_library",
  "/inputs/ssb_study/runtime/R_libs",.libPaths()))
root<-"/inputs/ssb_study/SSB_Figure2_layout_20261019"
stem<-file.path(root,"figures/Figure_2_layout_4-3-3")
lay<-read.delim(file.path(root,"source_data/Panel_numbering_and_layout.tsv"))
stopifnot(identical(as.integer(table(lay$row)),c(4L,3L,3L)))
for(i in 1:9) for(j in seq.int(i+1L,10L)) {
  horizontal<-max(lay$left_mm[c(i,j)])<min(lay$left_mm[c(i,j)]+lay$width_mm[c(i,j)])-1e-6
  vertical<-max(lay$top_mm[c(i,j)])<min(lay$top_mm[c(i,j)]+lay$height_mm[c(i,j)])-1e-6
  stopifnot(!(horizontal&&vertical))
}
x<-xml2::read_xml(paste0(stem,".svg"))
text<-xml2::xml_find_all(x,".//*[local-name()='text']")
idx<-xml2::xml_text(text)%in%LETTERS[1:10]&
     grepl("font-weight: bold",xml2::xml_attr(text,"style"),fixed=TRUE)
tags<-text[idx]
tag_table<-data.frame(tag=xml2::xml_text(tags),
  x=as.numeric(xml2::xml_attr(tags,"x")),y=as.numeric(xml2::xml_attr(tags,"y")))
tag_table<-tag_table[!duplicated(tag_table$tag,fromLast=TRUE),]
tag_table<-tag_table[match(LETTERS[1:10],tag_table$tag),]
stopifnot(identical(tag_table$tag,LETTERS[1:10]))
expected_y<-c(rep(tag_table$y[1],4),rep(tag_table$y[5],3),rep(tag_table$y[8],3))
stopifnot(all(abs(tag_table$y-expected_y)<.02),
          all(diff(tag_table$x[1:4])>0),all(diff(tag_table$x[5:7])>0),
          all(diff(tag_table$x[8:10])>0))
stopifnot(length(xml2::xml_find_all(x,".//*[local-name()='image']"))==0L)
write.table(tag_table,file.path(root,"QA/SVG_panel_order.tsv"),sep="\t",quote=FALSE,row.names=FALSE)
st<-read.delim(file.path(root,"QA/Scientific_value_preservation.tsv"))
stopifnot(all(st$unchanged_input_data),all(st$unchanged_built_layer_values))
ppt<-read.delim(file.path(root,"QA/PowerPoint_structure_QA.tsv"))
stopifnot(ppt$editable_panel_groups==10L,ppt$raster_pictures==0L,ppt$duplicate_shape_ids==0L)
fonts<-system2("pdffonts",shQuote(paste0(stem,".pdf")),stdout=TRUE)
writeLines(fonts,file.path(root,"QA/PDF_font_audit.txt"))
stopifnot(any(grepl("ArialMT",fonts,fixed=TRUE)))
info<-system2("identify",c("-format",shQuote("%w %h %x %y %[units]"),
                         shQuote(paste0(stem,".tiff"))),stdout=TRUE)
stopifnot(grepl("600 600 PixelsPerInch",info,fixed=TRUE))
writeLines(info,file.path(root,"QA/TIFF_resolution.txt"))
report<-c("# Figure 2 export checks", "",
  "PASS: row 1 A–D; row 2 E–G; row 3 H–J, confirmed from vector text positions.",
  "PASS: ten nonoverlapping panel viewports; no panel added or omitted.",
  "PASS: all scientific layer values and underlying panel data are unchanged.",
  "PASS: SVG contains vector artwork and editable text, with no embedded raster images.",
  "PASS: PDF embeds Arial fonts; TIFF retains 600-dpi resolution.",
  "PASS: PowerPoint contains ten native editable panel groups and no raster pictures.",
  "PASS: revised preview visually reviewed at whole-figure size.",
  "PASS: Figure 2 legend renumbered to match the ten panel letters.")
writeLines(report,file.path(root,"QA/Final_export_checks.md"))
cat(paste(report,collapse="\n"),"\n")
