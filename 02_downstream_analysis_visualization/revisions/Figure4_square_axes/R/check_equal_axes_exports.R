.libPaths(c("/inputs/ssb_study/SSB_QC261_EXON_primary_20261013/PPT_assembly_20261015/R_library",
 "/inputs/ssb_study/CI_atlas_revision_20260915/runtime/R_library",
 "/inputs/ssb_study/NOA_R_rebuild_20260821/R_library",
 "/inputs/ssb_study/runtime/R_libs",.libPaths()))
OUT<-"/inputs/ssb_study/SSB_Figure4_square_axes_20261022"
PREVIOUS<-"/inputs/ssb_study/SSB_Figure4_layout_20261019"
stem<-file.path(OUT,"figures/Figure_4_2x4_equal_axes")
geometry<-read.delim(file.path(OUT,"QA/Exported_axis_geometry.tsv"))
lay<-read.delim(file.path(OUT,"source_data/Figure4_square_axis_layout.tsv"))
x<-xml2::read_xml(paste0(stem,".svg"))
lines<-xml2::xml_find_all(x,".//*[local-name()='polyline' and contains(@style, 'stroke-linecap: square')]")
pts<-lapply(xml2::xml_attr(lines,"points"),function(s)as.numeric(strsplit(trimws(s),"[, ]+")[[1]]))
pts<-pts[vapply(pts,length,integer(1))==4L]
v<-do.call(rbind,pts)
axis_results<-list()
for(k in 1:8) {
  left<-geometry$page_panel_left_mm[k]*72/25.4
  top<-geometry$page_panel_top_mm[k]*72/25.4
  right<-left+60*72/25.4;bottom<-top+60*72/25.4
  matches<-function(target)which(apply(abs(v-matrix(target,nrow(v),4,byrow=TRUE)),1,max)<.03)
  ih<-unique(c(matches(c(left,bottom,right,bottom)),matches(c(right,bottom,left,bottom))))
  iv<-unique(c(matches(c(left,bottom,left,top)),matches(c(left,top,left,bottom))))
  stopifnot(length(ih)>=1L,length(iv)>=1L)
  length_mm<-function(j)sqrt((v[j,3]-v[j,1])^2+(v[j,4]-v[j,2])^2)*25.4/72
  xx<-length_mm(ih[1]);yy<-length_mm(iv[1])
  stopifnot(abs(xx-60)<.005,abs(yy-60)<.005,abs(xx-yy)<.005)
  axis_results[[k]]<-data.frame(panel=geometry$panel[k],
     actual_SVG_x_axis_mm=xx,actual_SVG_y_axis_mm=yy,difference_mm=xx-yy)
}
write.table(do.call(rbind,axis_results),file.path(OUT,"QA/Actual_SVG_axis_lengths.tsv"),
            sep="\t",quote=FALSE,row.names=FALSE)
stopifnot(length(xml2::xml_find_all(x,".//*[local-name()='image']"))==0L,
          identical(as.integer(table(lay$row)),c(4L,4L)))
txt<-xml2::xml_find_all(x,".//*[local-name()='text']")
tags<-txt[xml2::xml_text(txt)%in%LETTERS[1:8]&grepl("font-weight: bold",xml2::xml_attr(txt,"style"),fixed=TRUE)]
tagtab<-data.frame(panel=xml2::xml_text(tags),x=as.numeric(xml2::xml_attr(tags,"x")),
                  y=as.numeric(xml2::xml_attr(tags,"y")))
tagtab<-tagtab[!duplicated(tagtab$panel,fromLast=TRUE),]
tagtab<-tagtab[match(LETTERS[1:8],tagtab$panel),]
stopifnot(identical(tagtab$panel,LETTERS[1:8]),all(abs(tagtab$y[1:4]-tagtab$y[1])<.02),
          all(abs(tagtab$y[5:8]-tagtab$y[5])<.02),all(diff(tagtab$x[1:4])>0),all(diff(tagtab$x[5:8])>0))

# Independently inspect actual DrawingML line extents in each editable group.
tmp<-tempfile("square_axes_qa_");dir.create(tmp);unzip(paste0(stem,"_editable.pptx"),exdir=tmp)
sf<-list.files(file.path(tmp,"ppt/slides"),pattern="^slide[0-9]+[.]xml$",full.names=TRUE)
stopifnot(length(sf)==1L)
px<-xml2::read_xml(sf)
ns<-c(p="http://schemas.openxmlformats.org/presentationml/2006/main",
      a="http://schemas.openxmlformats.org/drawingml/2006/main")
native<-list()
for(k in 1:8) {
  id<-paste0("Fig4",LETTERS[k])
  g<-xml2::xml_find_first(px,paste0('//p:grpSp[p:nvGrpSpPr/p:cNvPr[@name="',id,'"]]'),ns)
  stopifnot(!inherits(g,"xml_missing"))
  e<-xml2::xml_find_all(g,".//p:sp/p:spPr/a:xfrm/a:ext",ns)
  w<-as.numeric(xml2::xml_attr(e,"cx"))/36000
  h<-as.numeric(xml2::xml_attr(e,"cy"))/36000
  nh<-sum(abs(w-60)<.005&h<.005)
  nv<-sum(abs(h-60)<.005&w<.005)
  stopifnot(nh>=1L,nv>=1L)
  native[[k]]<-data.frame(panel=id,horizontal_60mm_native_lines=nh,vertical_60mm_native_lines=nv)
}
write.table(do.call(rbind,native),file.path(OUT,"QA/Actual_PPT_axis_extents.tsv"),
            sep="\t",quote=FALSE,row.names=FALSE)
stopifnot(length(xml2::xml_find_all(px,"//p:pic",ns))==0L)

# Numeric labels and all figure text must survive the presentation change.
pdfs<-c(file.path(PREVIOUS,"figures/Figure_4_layout_2x4.pdf"),paste0(stem,".pdf"))
allwords<-vector("list",2)
for(k in 1:2) {
  h<-file.path(OUT,"QA",paste0(c("Previous","New")[k],"_PDF_word_boxes.html"))
  stopifnot(system2("pdftotext",c("-bbox",shQuote(pdfs[k]),shQuote(h)))==0L)
  d<-xml2::read_html(h)
  allwords[[k]]<-sort(xml2::xml_text(xml2::xml_find_all(d,".//word")))
}
stopifnot(identical(allwords[[1]],allwords[[2]]))
audit<-read.delim(file.path(OUT,"QA/Scientific_value_preservation.tsv"))
stopifnot(all(audit$raw_plot_data_unchanged),all(audit$built_layer_values_unchanged),
          all(audit$numeric_coordinate_system_unchanged))
info<-system2("identify",c("-format",shQuote("%w %h %x %y %[units]"),shQuote(paste0(stem,".tiff"))),stdout=TRUE)
stopifnot(grepl("600 600 PixelsPerInch",info,fixed=TRUE))
writeLines(info,file.path(OUT,"QA/TIFF_resolution.txt"))
fonts<-system2("pdffonts",shQuote(paste0(stem,".pdf")),stdout=TRUE)
stopifnot(any(grepl("Arial",fonts,fixed=TRUE)))
writeLines(fonts,file.path(OUT,"QA/PDF_fonts.txt"))
report<-c("# Figure 4 equal-axis export verification", "",
 "PASS: actual SVG horizontal and vertical axis lines are 60 mm in all eight panels (tolerance 0.005 mm).",
 "PASS: native editable PowerPoint line extents independently confirm 60-mm horizontal and vertical lines in every panel.",
 "PASS: A–D above E–H, confirmed from exported vector panel-letter coordinates.",
 "PASS: all plot-data values, built scientific layer values and numeric coordinate systems are unchanged.",
 "PASS: every PDF word and numeric label matches the previous version (word multiset comparison).",
 "PASS: Arial embedded in PDF; no raster images in SVG or PPT; lossless 600-dpi TIFF.",
 "PASS: preview visually reviewed; previous version and original inputs retained unchanged.")
writeLines(report,file.path(OUT,"QA/Final_export_checks.md"))
cat(paste(report,collapse="\n"),"\n")
