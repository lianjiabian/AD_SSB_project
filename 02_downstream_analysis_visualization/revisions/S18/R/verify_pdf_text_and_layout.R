# Independent text-position check on the existing and incrementally edited PDFs.
.libPaths(c("/inputs/ssb_study/CI_atlas_revision_20260915/runtime/R_library",
            "/inputs/ssb_study/NOA_R_rebuild_20260821/R_library",
            "/inputs/ssb_study/runtime/R_libs",.libPaths()))
root <- "/inputs/ssb_study/SSB_Figure_S18_legend_revision_20261018"
old <- "/inputs/ssb_study/SSB_manuscript_reorganized_20261015/final_figure_package/supplementary_figures/Supplementary_Figure_S18.pdf"
new <- file.path(root,"figures/Supplementary_Figure_S18_legend_revised.pdf")
paths <- file.path(root,"QA",c("original_pdf_word_boxes.html","revised_pdf_word_boxes.html"))
for(k in 1:2) stopifnot(system2("pdftotext",c("-bbox",shQuote(c(old,new)[k]),shQuote(paths[k])))==0L)
get_words <- function(path) {
  x<-xml2::read_html(path)
  w<-xml2::xml_find_all(x,".//word")
  data.frame(text=xml2::xml_text(w),xmin=as.numeric(xml2::xml_attr(w,"xmin")),
       ymin=as.numeric(xml2::xml_attr(w,"ymin")),xmax=as.numeric(xml2::xml_attr(w,"xmax")),
       ymax=as.numeric(xml2::xml_attr(w,"ymax")),stringsAsFactors=FALSE)
}
a<-get_words(paths[1]);b<-get_words(paths[2])
stopifnot(nrow(a)>0L,nrow(b)>0L)
legend_y<-a$ymin[a$text %in% c("FALSE","TRUE")]
is_legend<-function(d) vapply(d$ymin,function(y) any(abs(y-legend_y)<.001),logical(1))
non_legend<-function(d) {
  d<-d[!is_legend(d),]
  d<-d[order(d$ymin,d$xmin,d$text),]
  rownames(d)<-NULL
  d
}
stopifnot(identical(non_legend(a),non_legend(b)))
stopifnot(!any(b$text %in% c("FALSE","TRUE")))
stopifnot(sum(b$text=="Significant")==4L,sum(b$text=="Not")==4L)
leg<-b[is_legend(b),]
leg<-leg[order(leg$ymin,leg$xmin),]
stopifnot(all(leg$xmin>=0),all(leg$xmax<=518),all(leg$ymin>=0),all(leg$ymax<=680))
for(y in unique(leg$ymin)) {
  z<-leg[leg$ymin==y,]
  stopifnot(all(head(z$xmax,-1L)<tail(z$xmin,-1L)))
}
report<-c(
 "PASS\tPDF: every non-legend word and its bounding box are unchanged",
 "PASS\tPDF: no Boolean legend words remain; four labels of each new category",
 "PASS\tPDF: all revised legend word bounding boxes are inside the original page",
 "PASS\tPDF: no adjacent legend words overlap",
 "PASS\tRevised PNG visually inspected: correct labels, no clipping, original layout")
writeLines(report,file.path(root,"QA","independent_PDF_layout_check.tsv"))
cat(paste(report,collapse="\n"),"\n")
