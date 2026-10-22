.libPaths(c("/inputs/ssb_study/SSB_QC261_EXON_primary_20261013/PPT_assembly_20261015/R_library",
 "/inputs/ssb_study/CI_atlas_revision_20260915/runtime/R_library",
 "/inputs/ssb_study/NOA_R_rebuild_20260821/R_library",
 "/inputs/ssb_study/runtime/R_libs",.libPaths()))
OUT<-"/inputs/ssb_study/SSB_Figure3_layout_20261019"
SRC<-"/inputs/ssb_study/SSB_manuscript_reorganized_20261015/final_figure_package"
stem<-file.path(OUT,"figures/Figure_3_layout_AB_2to1")
lay<-read.delim(file.path(OUT,"source_data/Figure3_layout.tsv"))
old<-readRDS(file.path(SRC,"mapping_and_QC/figure_registry.rds"))$layouts$Figure3
shift<-old$height_mm[2]
stopifnot(lay$width_mm[1]==122,lay$width_mm[2]==61,lay$top_mm[1]==0,lay$top_mm[2]==0,
          abs(lay$height_mm[1]-old$height_mm[1])<1e-8,abs(lay$height_mm[2]-old$height_mm[1])<1e-8,
          all(abs((old$top_mm[3:6]-lay$top_mm[3:6])-shift)<1e-8),
          identical(lay$width_mm[3:6],old$width_mm[3:6]),
          all(abs(lay$height_mm[3:6]-old$height_mm[3:6])<1e-8))
read_text<-function(path) {
 x<-xml2::read_xml(path)
 z<-xml2::xml_find_all(x,".//*[local-name()='text']")
 tx<-xml2::xml_attr(z,"transform")
 xx<-suppressWarnings(as.numeric(xml2::xml_attr(z,"x")))
 yy<-suppressWarnings(as.numeric(xml2::xml_attr(z,"y")))
 i<-which(is.na(yy)&!is.na(tx))
 for(k in i) {
   vals<-strsplit(sub(".*translate\\(([^)]+)\\).*","\\1",tx[k]),",| +")[[1]]
   xx[k]<-as.numeric(vals[1]);yy[k]<-as.numeric(vals[2])
 }
 d<-data.frame(text=xml2::xml_text(z),x=xx,y=yy,style=xml2::xml_attr(z,"style"),
               textLength=xml2::xml_attr(z,"textLength"),stringsAsFactors=FALSE)
 attr(d,"raster_images")<-length(xml2::xml_find_all(x,".//*[local-name()='image']"))
 d
}
a<-read_text(file.path(SRC,"main_figures/Figure_3.svg"))
b<-read_text(paste0(stem,".svg"))
stopifnot(attr(b,"raster_images")==0L)
aa<-a[!is.na(a$y)&a$y>=old$top_mm[3]*72/25.4-.1,]
bb<-b[!is.na(b$y)&b$y>=lay$top_mm[3]*72/25.4-.1,]
aa$y<-aa$y-shift*72/25.4
aa<-aa[order(aa$text,aa$x,aa$y),];bb<-bb[order(bb$text,bb$x,bb$y),]
rownames(aa)<-rownames(bb)<-NULL
stopifnot(nrow(aa)==nrow(bb),identical(aa$text,bb$text),identical(aa$style,bb$style),
          identical(aa$textLength,bb$textLength),max(abs(aa$x-bb$x))<.02,
          max(abs(aa$y-bb$y))<.02)
checks<-data.frame(check=c("A:B width ratio","Top-row height equals original A row",
  "Old B row removed","C-F dimensions unchanged","C-F translated only",
  "C-F vector text, fonts and local text positions unchanged","SVG raster images"),
  result=c("2:1","PASS","PASS","PASS","PASS","PASS","0"))
write.table(checks,file.path(OUT,"QA/Final_checks.tsv"),sep="\t",row.names=FALSE,quote=FALSE)
fonts<-system2("pdffonts",shQuote(paste0(stem,".pdf")),stdout=TRUE)
stopifnot(any(grepl("Arial",fonts,fixed=TRUE)))
writeLines(fonts,file.path(OUT,"QA/PDF_fonts.txt"))
info<-system2("identify",c("-format",shQuote("%w %h %x %y %[units]"),shQuote(paste0(stem,".tiff"))),stdout=TRUE)
stopifnot(grepl("600 600 PixelsPerInch",info,fixed=TRUE))
writeLines(info,file.path(OUT,"QA/TIFF_resolution.txt"))
pd<-tempfile("fig3_check_");dir.create(pd);unzip(paste0(stem,"_editable.pptx"),exdir=pd)
sf<-list.files(file.path(pd,"ppt/slides"),pattern="^slide[0-9]+[.]xml$",full.names=TRUE)
stopifnot(length(sf)==1L)
x<-xml2::read_xml(sf)
groups<-xml2::xml_find_all(x,".//*[local-name()='grpSp']/*[local-name()='nvGrpSpPr']/*[local-name()='cNvPr']")
stopifnot(length(groups)==6L,setequal(xml2::xml_attr(groups,"name"),paste0("Fig3",LETTERS[1:6])),
          length(xml2::xml_find_all(x,".//*[local-name()='pic']"))==0L)
cat("PASS: A/B 2:1; original A-row height; B row removed; C-F local positions and dimensions unchanged.\n")
cat("PASS: editable PDF/SVG/PPT; six native PPT groups, no raster pictures; 600-dpi TIFF.\n")
