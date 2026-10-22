# Existing-file edit only. No scientific plot, data, model or ggplot object is run.
.libPaths(c(
  "/inputs/ssb_study/CI_atlas_revision_20260915/runtime/R_library",
  "/inputs/ssb_study/NOA_R_rebuild_20260821/R_library",
  "/inputs/ssb_study/runtime/R_libs", .libPaths()))
stopifnot(requireNamespace("png", quietly=TRUE),
          requireNamespace("ragg", quietly=TRUE),
          requireNamespace("systemfonts", quietly=TRUE))
library(grid)
root <- "/inputs/ssb_study/SSB_Figure_S18_legend_revision_20261018"
src <- "/inputs/ssb_study/SSB_manuscript_reorganized_20261015/final_figure_package/supplementary_figures"
source(file.path(root, "R/pdf_edit_helpers.R"))
dir.create(file.path(root,"figures"), recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(root,"QA"), recursive=TRUE, showWarnings=FALSE)
stem <- "Supplementary_Figure_S18"
out <- file.path(root,"figures",paste0(stem,"_legend_revised"))
inputs <- file.path(src,paste0(stem,c(".svg",".pdf",".png",".tiff")))
hash_before <- tools::md5sum(inputs)
labels <- c("Not significant", "Significant (BH-adjusted P < 0.05)")
widths <- systemfonts::string_width(labels, family="Arial", size=8.5, res=7200)/100
stopifnot(all(abs(widths-c(53.40,128.15)) < .02))
pw <- 259.37
key_w <- 17.28
pad <- 5.98
gap <- 10
total <- key_w*2 + pad*2 + sum(widths) + gap
left <- (pw-total)/2
key_left <- c(left, left+key_w+pad+widths[1]+gap)
text_x <- key_left+key_w+pad
key_cx <- key_left+key_w/2
qa <- character()
check <- function(name, pass) {
  qa <<- c(qa,sprintf("%s\t%s", if(isTRUE(pass)) "PASS" else "FAIL",name))
  if (!isTRUE(pass)) stop(name)
}

# 1. Edit only the seven pre-existing SVG legend elements in each panel.
svg <- readLines(inputs[1], warn=FALSE)
old_svg <- svg
idx_false <- grep(">FALSE</text>", svg, fixed=TRUE)
idx_true <- grep(">TRUE</text>", svg, fixed=TRUE)
stopifnot(length(idx_false)==4L,length(idx_true)==4L)
legend_lines <- integer()
cy_svg <- numeric(4)
for (k in 1:4) {
  a <- idx_false[k]-5L
  ids <- seq.int(a,idx_true[k])
  stopifnot(length(ids)==7L, startsWith(svg[a],"<rect"),
            startsWith(svg[a+2L],"<circle"),startsWith(svg[a+4L],"<circle"))
  legend_lines <- c(legend_lines,ids)
  offset <- if(k %% 2L == 0L) pw else 0
  cy <- as.numeric(sub(".*cy='([^']+)'.*","\\1",svg[a+2L]))
  cy_svg[k] <- cy
  set_att <- function(s, att, val) sub(paste0(att,"='[^']+'"),
                         sprintf("%s='%.2f'",att,val),s)
  svg[a] <- set_att(svg[a],"x",offset+left-pad)
  svg[a] <- set_att(svg[a],"width",total+2*pad)
  for(j in 1:2) {
    rect_id <- a+2*j-1L
    circle_id <- a+2*j
    text_id <- if(j==1L) idx_false[k] else idx_true[k]
    svg[rect_id] <- set_att(svg[rect_id],"x",offset+key_left[j])
    svg[circle_id] <- set_att(svg[circle_id],"cx",offset+key_cx[j])
    svg[text_id] <- set_att(svg[text_id],"x",offset+text_x[j])
    svg[text_id] <- sub("textLength='[^']+'",sprintf("textLength='%.2fpx'",widths[j]),svg[text_id])
    svg[text_id] <- sub(if(j==1L) ">FALSE</text>" else ">TRUE</text>",
            paste0(">",gsub("<","&lt;",labels[j],fixed=TRUE),"</text>"),svg[text_id],fixed=TRUE)
  }
}
writeLines(svg,paste0(out,".svg"),useBytes=TRUE)
check("SVG: all non-legend elements are byte-for-byte identical",
      identical(old_svg[-legend_lines],svg[-legend_lines]))
check("SVG: four exact significant labels and four exact not-significant labels",
      sum(grepl(">Not significant</text>",svg,fixed=TRUE))==4L &&
      sum(grepl(">Significant (BH-adjusted P &lt; 0.05)</text>",svg,fixed=TRUE))==4L)
check("SVG: no Boolean legend labels remain",
      !any(grepl(">TRUE</text>|>FALSE</text>",svg)))
check("SVG: original dimensions unchanged",identical(old_svg[2],svg[2]))

# 2. Incrementally edit the existing PDF content stream. Preserve the complete
# original PDF byte sequence and append only revised legend/resource objects.
p <- read_pdf(inputs[2])
old_lines <- strsplit(raw_text(pdf_stream(p$get(4),p$get)),"\n",fixed=TRUE)[[1]]
tjs <- grep("[(F)",old_lines,fixed=TRUE)
stopifnot(length(tjs)==4L)
starts <- vapply(tjs,function(i) tail(which(grepl("^1 1 1 rg .* 29\\.234 re f$",old_lines[seq_len(i)])),1),integer(1))
new_blocks <- vector("list",4)
base_y <- numeric(4)
pdf_key_x <- matrix(NA_real_,4,2)
for(k in 1:4) {
  block <- old_lines[seq.int(starts[k],tjs[k])]
  switch <- which(block=="1 1 1 rg /a0 gs")[1]
  bt <- which(block=="BT")[1]
  stopifnot(length(switch)==1L,length(bt)==1L)
  offset <- if(k %% 2L == 0L) 259.371 else 0
  xold <- as.numeric(strsplit(trimws(block[2])," +")[[1]][1])
  xold2 <- as.numeric(strsplit(trimws(block[switch+1L])," +")[[1]][1])
  pdf_key_x[k,] <- c(xold,xold2)+8.641
  base_y[k] <- as.numeric(strsplit(trimws(block[bt+1L])," +")[[1]][6])
  # Translate existing vector key paths without changing their colours,
  # alpha, shapes or stroke widths. Keep the existing text-line matrix so
  # the following panel-label positioning instructions stay unchanged.
  new_blocks[[k]] <- c(block[1],
      "q",sprintf("1 0 0 1 %.5f 0 cm",offset+key_left[1]-xold),
      block[seq.int(2L,switch-1L)],"Q",
      "q",sprintf("1 0 0 1 %.5f 0 cm",offset+key_left[2]-xold2),
      block[seq.int(switch,bt-2L)],"Q",block[seq.int(bt-1L,length(block)-1L)])
}
keep <- rep(TRUE,length(old_lines))
for(k in 1:4) keep[seq.int(starts[k],tjs[k])] <- FALSE
science_before <- old_lines[keep]
new_lines <- old_lines
for(k in 4:1) new_lines <- c(new_lines[seq_len(starts[k]-1L)],new_blocks[[k]],
                            new_lines[seq.int(tjs[k]+1L,length(new_lines))])
# Audit that deleting the altered legend segments restores exactly the old
# scientific drawing commands, including every data point and panel label.
science_after <- new_lines
for(k in 4:1) {
  at <- which(science_after==new_blocks[[k]][1])
  at <- at[vapply(at,function(a) identical(science_after[seq.int(a,a+length(new_blocks[[k]])-1L)],new_blocks[[k]]),logical(1))]
  stopifnot(length(at)==1L)
  science_after <- science_after[-seq.int(at,at+length(new_blocks[[k]])-1L)]
}
check("PDF: scientific drawing commands outside legends are identical",
      identical(science_before,science_after))

# Obtain the same Arial font and its kerning instructions from an R Cairo
# text-only PDF; import only the needed resources, not a redraw of the figure.
font_pdf <- file.path(root,"QA","legend_font_resource.pdf")
grDevices::cairo_pdf(font_pdf,width=518/72,height=680/72,family="Arial")
grid.newpage()
grid.text(labels[1],x=.1,y=.8,just="left",gp=gpar(fontfamily="Arial",fontsize=8.5))
grid.text(labels[2],x=.1,y=.7,just="left",gp=gpar(fontfamily="Arial",fontsize=8.5))
dev.off()
f <- read_pdf(font_pdf)
fres <- raw_text(f$get(3))
font_id <- as.integer(sub(".*?/f-0-0 ([0-9]+) 0 R.*","\\1",fres))
fcontent <- raw_text(pdf_stream(f$get(4),f$get))
operators <- regmatches(fcontent,gregexpr("\\[[^]]*\\]TJ|\\([^\\n]*\\)Tj",fcontent,perl=TRUE))[[1]]
stopifnot(length(operators)==2L)
objects <- list()
for(id in seq_len(f$size-1L)) if(f$rows[id+1L,1] %in% c(1L,2L)) {
  obj <- f$get(id)
  if(!grepl("/Type /XRef",pdf_header(obj),fixed=TRUE))
    objects[[as.character(id+p$size)]] <- replace_pdf_refs(obj,p$size)
}
resource <- raw_text(p$get(3))
resource <- sub("/Font <<",sprintf("/Font <<\n      /S18Legend %d 0 R",font_id+p$size),resource,fixed=TRUE)
objects[["3"]] <- ascii(resource)
overlay <- c("q","1 0 0 -1 0 680 cm","0 0 0 rg /a0 gs")
for(k in 1:4) for(j in 1:2) {
  offset <- if(k %% 2L == 0L) 259.371 else 0
  overlay <- c(overlay,"BT",sprintf("8.5 0 0 -8.5 %.6f %.6f Tm",offset+text_x[j],base_y[k]),
               "/S18Legend 1 Tf",operators[j],"ET")
}
overlay <- c(overlay,"Q")
objects[["4"]] <- stream_object(paste(c("q",new_lines,"Q",overlay),collapse="\n"))
append_pdf_revision(p,objects,paste0(out,".pdf"))
after_pdf <- read_raw(paste0(out,".pdf"))
check("PDF: the original file byte sequence is preserved as the incremental-update prefix",
      identical(after_pdf[seq_along(p$bytes)],p$bytes))

# 3. Exact raster file edits. Decode existing pixels, replace only two blank
# legend bands, and copy the original legend keys without recolouring them.
# ImageMagick is a read-only TIFF pixel decoder, never an image renderer here.
native_read <- function(path,ext) {
  if(ext=="png") {
    # nativeRaster stores row-major pixels despite its R matrix dimensions.
    # Convert to an ordinary column-major matrix before spatial indexing.
    x <- png::readPNG(path,native=TRUE)
    return(matrix(as.integer(x),nrow=nrow(x),ncol=ncol(x),byrow=TRUE))
  }
  meta <- strsplit(system2("identify",c("-format",shQuote("%w %h"),shQuote(path)),stdout=TRUE)," +")[[1]]
  wh <- as.integer(meta)
  cmd <- paste("convert",shQuote(path),"-depth 8 rgba:-")
  con <- pipe(cmd,"rb")
  on.exit(close(con))
  pix <- readBin(con,integer(),n=prod(wh),size=4L,endian="little")
  stopifnot(length(pix)==prod(wh))
  dim(pix) <- wh
  pix <- t(pix)
  pix
}
write_tiff_deflate <- function(img,path,dpi) {
  # Standard little-endian RGB-alpha TIFF, one losslessly deflated strip.
  h<-nrow(img); w<-ncol(img)
  payload <- memCompress(writeBin(as.vector(t(img)),raw(),size=4L,endian="little"),"gzip")
  tags <- c(256,257,258,259,262,273,277,278,279,282,283,284,296,338)
  n<-length(tags); extra<-8+2+12*n+4
  bits_off<-extra; xres_off<-extra+8; yres_off<-extra+16; data_off<-extra+24
  types<-c(4,4,3,3,3,4,3,4,4,5,5,3,3,3)
  counts<-c(1,1,4,1,1,1,1,1,1,1,1,1,1,1)
  values<-c(w,h,bits_off,8,2,data_off,4,h,length(payload),xres_off,yres_off,1,2,2)
  con<-file(path,"wb"); on.exit(close(con))
  u16<-function(x) writeBin(as.integer(x),con,size=2L,endian="little")
  u32<-function(x) writeBin(as.integer(x),con,size=4L,endian="little")
  writeBin(ascii("II"),con);u16(42);u32(8);u16(n)
  for(i in seq_len(n)) {u16(tags[i]);u16(types[i]);u32(counts[i]);
    if(types[i]==3L && counts[i]==1L) {u16(values[i]);u16(0)} else u32(values[i])}
  u32(0);u16(rep(8,4));u32(c(dpi,1,dpi,1));writeBin(payload,con)
}
raster_qa <- list()
for(ext in c("png","tiff")) {
  original <- native_read(file.path(src,paste0(stem,".",ext)),ext)
  edited <- original
  dpi <- if(ext=="png") 160L else 600L
  h<-nrow(original);w<-ncol(original)
  sx<-w/518.74;sy<-h/680.31
  bands<-lapply(c(1L,3L),function(k) c(floor((cy_svg[k]-15)*sy)+1L,
                                      ceiling((cy_svg[k]+15)*sy)))
  modified_rows<-integer()
  for(row in 1:2) {
    band<-bands[[row]]; tileh<-diff(band)+1L
    tmp<-file.path(root,"QA",paste0("legend_text_band_",ext,"_",row,".png"))
    ragg::agg_png(tmp,width=w,height=tileh,units="px",res=dpi,background="white")
    grid.newpage()
    for(col in 1:2) for(j in 1:2) {
      k<-(row-1L)*2L+col
      grid.text(labels[j],x=unit(((col-1)*pw+text_x[j])*sx,"native"),
        y=unit(tileh-(cy_svg[k]*sy-band[1]+1),"native"),
        just=c("left","centre"),
        gp=gpar(fontfamily="Arial",fontsize=8.5),
        vp=viewport(xscale=c(0,w),yscale=c(0,tileh)))
    }
    dev.off()
    tile<-native_read(tmp,"png")
    for(col in 1:2) for(j in 1:2) {
      k<-(row-1L)*2L+col
      old_cx<-as.numeric(sub(".*cx='([^']+)'.*","\\1",old_svg[idx_false[k]-5L+2*j]))
      cy<-cy_svg[k]
      # The rectangular source tile contains the exact original key pixels.
      xx<-seq.int(floor((old_cx-3)*sx)+1L,ceiling((old_cx+3)*sx))
      yy<-seq.int(floor((cy-3)*sy)+1L,ceiling((cy+3)*sy))
      dx<-round((((col-1)*pw+key_cx[j])-old_cx)*sx)
      tile[yy-band[1]+1L,xx+dx]<-original[yy,xx]
      check(sprintf("%s: panel %s key %d keeps exact original pixels",ext,LETTERS[k],j),
            identical(unclass(tile[yy-band[1]+1L,xx+dx]),unclass(original[yy,xx])))
    }
    edited[seq.int(band[1],band[2]),]<-tile
    modified_rows<-c(modified_rows,seq.int(band[1],band[2]))
  }
  check(paste0(ext,": pixels outside legend bands unchanged"),
        identical(original[-modified_rows,,drop=FALSE],edited[-modified_rows,,drop=FALSE]))
  if(ext=="png") {
    packed<-structure(as.vector(t(edited)),dim=dim(edited),class="nativeRaster")
    png::writePNG(packed,paste0(out,".png"),dpi=c(dpi,dpi))
  } else
    write_tiff_deflate(edited,paste0(out,".tiff"),dpi)
  reread<-native_read(paste0(out,".",ext),ext)
  check(paste0(ext,": saved dimensions unchanged"),identical(dim(original),dim(reread)))
  check(paste0(ext,": lossless saved-pixel round trip"),identical(as.integer(edited),as.integer(reread)))
  check(paste0(ext,": saved pixels outside legend bands unchanged"),
        identical(original[-modified_rows,,drop=FALSE],reread[-modified_rows,,drop=FALSE]))
  raster_qa[[ext]]<-data.frame(format=ext,width=w,height=h,dpi=dpi,
                    changed_pixels=sum(original!=reread),
                    changed_pixels_outside_legend=0L)
  rm(original,edited,reread);gc()
}
check("Original four figure files retain their original checksums",
      identical(hash_before,tools::md5sum(inputs)))
write.table(data.frame(file=basename(inputs),md5=unname(hash_before)),
       file.path(root,"QA","original_file_checksums.tsv"),sep="\t",row.names=FALSE,quote=FALSE)
write.table(do.call(rbind,raster_qa),file.path(root,"QA","raster_pixel_audit.tsv"),
            sep="\t",row.names=FALSE,quote=FALSE)
writeLines(c("# S18 legend-only edit: verification", "", paste0("- ",qa)),
           file.path(root,"QA","QA_report.md"))
writeLines(c("# Supplementary Figure S18 — legend-only revision", "",
  "Only the four Boolean legends were edited. No statistical calculation or scientific plot was rerun.",
  "", "- TRUE → Significant (BH-adjusted P < 0.05)","- FALSE → Not significant", "",
  "Point colours, significance classes, scientific graphics, axes, fonts, line widths and original dimensions are unchanged.",
  "Legend keys and text were repositioned within the existing legend bands to fit the longer labels.",
  "Original files are untouched. Revised vector PDF/SVG, preview PNG and lossless 600-dpi TIFF are in figures/.",
  "PDF is an incremental edit of the existing PDF, not a regenerated scientific plot.",
  "SVG non-legend elements are identical; raster pixels outside the legend bands are identical.",
  "", "Run R/modify_S18_legend_only.R with the project R environment. Verification is in QA/."),
  file.path(root,"README.md"))
writeLines(capture.output(sessionInfo()),file.path(root,"QA","sessionInfo.txt"))
cat(paste(qa,collapse="\n"),"\nDONE\n")
