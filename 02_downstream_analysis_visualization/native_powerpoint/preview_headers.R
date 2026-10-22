# Restore only reserved, non-data headers in R-generated slide previews.
# Native DrawingML positions have already been checked and do not need repair.
repair_preview_headers <- function(out, idx, W=200, H=280, LEFT=8.5) {
  rows <- list()
  for (nm in unique(idx$figure)) {
    f <- file.path(out,'previews',paste0(nm,'.png'))
    im <- png::readPNG(f)
    h <- dim(im)[1]; w <- dim(im)[2]
    lay <- idx[figure==nm]
    tmp <- tempfile('header_',tmpdir=dirname(f),fileext='.png')
    ragg::agg_png(tmp,width=w,height=h,units='px',res=150,background='white')
    grid::grid.newpage()
    grid::grid.raster(im,width=1,height=1,interpolate=FALSE)
    # All these strips were reserved before drawing the quantitative plots.
    grid::grid.rect(x=0,y=1,width=1,height=grid::unit(14,'mm'),
                    just=c('left','top'),gp=grid::gpar(fill='white',col=NA))
    title <- if(grepl('_S',nm))paste('Supplementary Figure',sub('Figure_','',nm)) else
      paste('Figure',sub('Figure','',nm))
    grid::grid.text(title,x=grid::unit(LEFT,'mm'),y=grid::unit(H-5,'mm'),
      just=c('left','top'),gp=grid::gpar(fontfamily='Arial',fontsize=12,fontface='bold'))
    mask <- matrix(FALSE,h,w)
    mask[seq_len(ceiling(14/H*h)+2L),] <- TRUE
    for(j in seq_len(nrow(lay))) {
      b <- lay[j]
      grid::grid.rect(x=grid::unit(b$left_mm,'mm'),y=grid::unit(H-b$top_mm,'mm'),
        width=grid::unit(b$width_mm,'mm'),height=grid::unit(3,'mm'),
        just=c('left','top'),gp=grid::gpar(fill='white',col=NA))
      grid::grid.text(b$tag,x=grid::unit(b$left_mm+.5,'mm'),
        y=grid::unit(H-b$top_mm-.4,'mm'),just=c('left','top'),
        gp=grid::gpar(fontfamily='Arial',fontsize=8.5,fontface='bold'))
      rr <- seq.int(max(1L,floor(b$top_mm/H*h)-2L),min(h,ceiling((b$top_mm+3)/H*h)+2L))
      cc <- seq.int(max(1L,floor(b$left_mm/W*w)-2L),min(w,ceiling((b$left_mm+b$width_mm)/W*w)+2L))
      mask[rr,cc] <- TRUE
    }
    dev.off()
    im2 <- png::readPNG(tmp)
    tolerance <- 1/255+1e-8
    changed <- abs(im[,,1]-im2[,,1])>tolerance |
      abs(im[,,2]-im2[,,2])>tolerance | abs(im[,,3]-im2[,,3])>tolerance
    rows[[length(rows)+1L]] <- data.table::data.table(figure=nm,
      quantitative_pixels_changed=sum(changed & !mask),header_only=all(!changed | mask))
    stopifnot(all(!changed | mask))
    stopifnot(file.copy(tmp,f,overwrite=TRUE))
    unlink(tmp)
  }
  data.table::rbindlist(rows)
}
