#!/usr/bin/env Rscript
# Run from the analysis project root. Existing analysis outputs are read-only.
# Optional environment variables: SSB_PROJECT_ROOT, SSB_PPT_OUT, SSB_PPT_TEST.
options(stringsAsFactors = FALSE)
project_root <- normalizePath(Sys.getenv('SSB_PROJECT_ROOT', unset = getwd()))
out <- Sys.getenv('SSB_PPT_OUT', unset = file.path(project_root, 'PPT_assembly_20261015'))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(file.path(out, 'R_library'),
            file.path(dirname(project_root), 'CI_atlas_revision_20260915/runtime/R_library'),
            file.path(dirname(project_root), 'NOA_R_rebuild_20260821/R_library'),
            file.path(dirname(project_root), 'runtime/R_libs'), .libPaths()))
packages <- c('officer', 'rvg', 'ggplot2', 'patchwork', 'data.table', 'xml2',
              'ragg', 'png', 'zip', 'openxlsx')
missing_packages <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages)) stop('Missing R packages: ', paste(missing_packages, collapse = ', '))
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(officer)})
setwd(project_root)
Sys.setenv(OMP_NUM_THREADS = '1', OPENBLAS_NUM_THREADS = '1', MKL_NUM_THREADS = '1')
setDTthreads(1L)
dir.create(file.path(out, 'previews'), showWarnings = FALSE)
dir.create(file.path(out, 'qa'), showWarnings = FALSE)

# Evaluate only the plot-definition section of the existing R source, before
# its rendering/export block. Disable all output helpers immediately after
# configuration: no original data, registry, Excel or statistical file is written.
before <- tools::md5sum(c(file.path(project_root, 'audit/figure_registry.rds'),
                         file.path(project_root, 'results/differential_summary.tsv'),
                         file.path(project_root, 'metadata/analysis_metadata.rds')))
e <- new.env(parent = globalenv())
exprs <- parse(file.path(project_root, 'code/08_figures.R'))
lhs <- function(expr) if (is.call(expr) && as.character(expr[[1]]) %in% c('<-', '='))
  paste(deparse(expr[[2]]), collapse = '') else ''
for (i in seq_along(exprs)) {
  if (identical(lhs(exprs[[i]]), 'render')) break
  eval(exprs[[i]], envir = e)
  if (i == 1L) {
    e$wr <- function(...) invisible(NULL)
    e$savebook <- function(...) invisible(NULL)
    e$logstage <- function(...) invisible(NULL)
  }
}
reg <- readRDS(file.path(project_root, 'audit/figure_registry.rds'))
ordered_supp <- reg$supplementary_layout[paste0('S', seq_len(28))]
figures <- c(reg$main, setNames(ordered_supp, paste0('Figure_S', seq_len(28))))
all_ids <- unname(unlist(figures))
stopifnot(length(figures) == 32L, length(all_ids) == 117L,
          !anyDuplicated(all_ids), setequal(all_ids, names(e$registry)))
e$FS <- 8.5
theme_set(e$theme_pub())
plots <- setNames(lapply(all_ids, function(id) e$registry[[id]]()), all_ids)

# Each row is an independently editable panel group. Dimensions are millimetres.
# The native vector canvas uses the existing journal-size panel typography.
W <- 200; H <- 280; LEFT <- 8.5; TOP <- 15; FW <- 183
make_layout <- function(rows, weights = rep(1, length(rows)), height = 250) {
  rh <- height * weights / sum(weights)
  yy <- c(0, head(cumsum(rh), -1L))
  rbindlist(lapply(seq_along(rows), function(i) {
    ids <- rows[[i]]
    data.table(panel = ids, left_mm = LEFT + (seq_along(ids)-1L) * FW/length(ids),
               top_mm = TOP + yy[i], width_mm = FW/length(ids), height_mm = rh[i])
  }))
}
layouts <- list(
  Figure1 = make_layout(list('Fig1A', paste0('Fig1', LETTERS[2:5]),
                            c('Fig1F', 'Fig1H'), 'Fig1G'), c(.85,1.3,1.05,.85)),
  Figure2 = make_layout(list(c('Fig2A','Fig2B'), c('Fig2C','Fig2D'),
                            c('Fig2E','Fig2F'), c('Fig2G','Fig2H'), 'Fig2I'),
                        c(1.1,1.1,.75,1.1,1)),
  Figure3 = make_layout(list('Fig3A','Fig3B',c('Fig3C','Fig3D'),c('Fig3E','Fig3F')),
                        c(1.1,.65,1.2,1.2)),
  Figure4 = make_layout(list(c('Fig4A1','Fig4A2','Fig4A3'), c('Fig4B','Fig4C'),
                            c('Fig4D1','Fig4D2'), c('Fig4E','Fig4F'), c('Fig4G','Fig4H')),
                        c(1.25,1.1,.85,1.45,1.5))
)
for (i in seq_len(28)) {
  nm <- paste0('Figure_S', i)
  ids <- figures[[nm]]
  rows <- if (i == 1L) list(ids[1], ids[2:3], ids[4]) else
    if (i == 7L) list(ids[1], ids[2:3]) else
      if (i == 8L || length(ids) <= 2L) as.list(ids) else
        split(ids, ceiling(seq_along(ids) / 2L))
  weights <- if (i == 1L) c(1.2,1.1,.8) else rep(1,length(rows))
  height <- if (i %in% c(1L,8L)) 250 else if (i == 13L) 150 else 240
  layouts[[nm]] <- make_layout(rows, weights, height)
}
for (nm in names(layouts)) {
  stopifnot(setequal(layouts[[nm]]$panel, figures[[nm]]))
  layouts[[nm]][, tag := sub('^Fig(?:S[0-9]+|[1-4])', '', panel, perl = TRUE)]
}
tagged <- function(id, tag) {
  p <- plots[[id]] + labs(tag = NULL)
  # Colour-bar legends default to small raster strips in ggplot2. Draw them
  # instead as native vector rectangles so even their colour keys are editable.
  for (a in c('fill','colour')) {
    sc <- p$scales$get_scales(a)
    if (!is.null(sc) && !sc$is_discrete()) {
      gd <- p$guides$get_guide(a)
      if (!(is.character(gd) && identical(gd,'none')) && !inherits(gd,'GuideNone')) {
        if (a=='fill') p <- p + guides(fill=guide_colourbar(display='rectangles')) else
          p <- p + guides(colour=guide_colourbar(display='rectangles'))
      }
    }
  }
  p
}
draw_panel <- function(p, tag, newpage=TRUE) {
  if (newpage) grid::grid.newpage()
  # Reserve a dedicated header strip: a tag must not overlap a y-axis label
  # when a plot has neither a title nor a subtitle.
  grid::pushViewport(grid::viewport(x=0,y=0,just=c('left','bottom'),
    width=1,height=grid::unit(1,'npc')-grid::unit(3,'mm')))
  grid::grid.draw(ggplot2::ggplotGrob(p))
  grid::popViewport()
  grid::grid.text(tag,x=grid::unit(.5,'mm'),y=grid::unit(1,'npc')-grid::unit(.4,'mm'),
    just=c('left','top'),gp=grid::gpar(fontfamily='Arial',fontsize=8.5,fontface='bold'))
}

# Patch only slide dimensions in a copy of the standard officer template.
template_dir <- tempfile('ppt_template_')
dir.create(template_dir)
utils::unzip(system.file('template/template.pptx',package='officer'), exdir=template_dir)
pres <- file.path(template_dir,'ppt/presentation.xml')
x <- xml2::read_xml(pres)
sz <- xml2::xml_find_first(x,'//p:sldSz',xml2::xml_ns(x))
xml2::xml_set_attr(sz,'cx',as.character(round(W/25.4*914400)))
xml2::xml_set_attr(sz,'cy',as.character(round(H/25.4*914400)))
xml2::xml_set_attr(sz,'type','custom')
xml2::write_xml(x,pres)
template <- file.path(out,'qa','portrait_template.pptx')
zip::zipr(template,files=list.files(template_dir,all.files=TRUE,no..=TRUE),root=template_dir)
ppt <- read_pptx(template)
while (length(ppt)) ppt <- remove_slide(ppt, index=length(ppt))
stopifnot(max(abs(unlist(slide_size(ppt))-c(W,H)/25.4)) < 1e-5)

title_for <- function(nm) if (grepl('_S',nm))
  paste('Supplementary Figure',sub('Figure_','',nm)) else
    paste('Figure',sub('Figure','',nm))
index <- list(); warning_log <- list()
test <- Sys.getenv('SSB_PPT_TEST') == '1'
selected <- if (test) c('Figure1','Figure2','Figure3','Figure4','Figure_S1',
                       'Figure_S8','Figure_S16','Figure_S23','Figure_S28') else names(figures)
for (nm in selected) {
  sl <- match(nm,selected)
  lay <- layouts[[nm]]
  title <- title_for(nm)
  cat(sprintf('SLIDE %02d %s (%d panels)\n',sl,nm,nrow(lay)));flush.console()
  ppt <- add_slide(ppt, layout='Blank',master='Office Theme')
  ppt <- ph_with(ppt,fpar(ftext(title,fp_text(font.family='Arial',font.size=12,bold=TRUE))),
                 location=ph_location(left=LEFT/25.4,top=3/25.4,width=FW/25.4,
                                      height=8/25.4,ph_label=paste0(nm,'_title')))
  for (j in seq_len(nrow(lay))) {
    b <- lay[j]
    p <- tagged(b$panel,b$tag)
    panel_tag <- b$tag
    ppt <- withCallingHandlers(ph_with(ppt,rvg::dml(code=draw_panel(p,panel_tag),editable=TRUE),
                  location=ph_location(left=b$left_mm/25.4,top=b$top_mm/25.4,
                                       width=b$width_mm/25.4,height=b$height_mm/25.4,
                                       ph_label=b$panel)),
      warning=function(w) {
        warning_log[[length(warning_log)+1L]] <<- data.table(figure=nm,panel=b$panel,message=conditionMessage(w))
        invokeRestart('muffleWarning')
      })
    index[[length(index)+1L]] <- data.table(slide=sl,figure=nm,panel=b$panel,
      tag=b$tag,left_mm=b$left_mm,top_mm=b$top_mm,width_mm=b$width_mm,height_mm=b$height_mm,
      source_excel=file.path('..','FINAL_SUBMISSION_PACKAGE','Figure_source_Excel','panels',paste0(b$panel,'_source_data.xlsx')),
      R_script=file.path('..','code','panels',paste0(b$panel,'.R')))
  }
  notes <- c(title,'',unlist(lapply(lay$panel,function(id)
    c(paste0(id,': ',reg$captions[[id]]$en),''))))
  ppt <- set_notes(ppt,value=notes,location=notes_location_type(type='body'))
  gc(verbose=FALSE)
}
deck_name <- if (test) 'TEST_All_Figures_editable.pptx' else 'SSB_All_Figures_editable_20261015.pptx'
deck <- file.path(out,deck_name)
cat('Writing PPTX ...\n');flush.console()
print(ppt,target=deck)

# Render the previews in a separate device-only pass. Interleaving temporary
# DrawingML devices with active ragg viewports can invalidate grid clipping.
for (nm in selected) {
  cat('PREVIEW ',nm,'\n');flush.console()
  lay <- layouts[[nm]]
  ragg::agg_png(file.path(out,'previews',paste0(nm,'.png')),
                width=W,height=H,units='mm',res=150,background='white')
  grid::grid.newpage()
  grid::grid.text(title_for(nm),x=grid::unit(LEFT,'mm'),y=grid::unit(H-5,'mm'),
                 just=c('left','top'),gp=grid::gpar(fontfamily='Arial',fontsize=12,fontface='bold'))
  for (j in seq_len(nrow(lay))) {
    b <- lay[j]
    p <- tagged(b$panel,b$tag)
    grid::pushViewport(grid::viewport(x=grid::unit(b$left_mm,'mm'),
          y=grid::unit(H-b$top_mm,'mm'),width=grid::unit(b$width_mm,'mm'),
          height=grid::unit(b$height_mm,'mm'),just=c('left','top')))
    draw_panel(p,b$tag,newpage=FALSE)
    grid::popViewport()
  }
  grDevices::dev.off()
}
idx <- rbindlist(index)
source(file.path(out,'preview_headers.R'))
preview_qa <- repair_preview_headers(out,idx,W,H,LEFT)
fwrite(preview_qa,file.path(out,'qa','Preview_header_QA.tsv'),sep='\t')
fwrite(idx,file.path(out,'Slide_panel_index.tsv'),sep='\t')
w <- openxlsx::createWorkbook()
openxlsx::addWorksheet(w,'Slide_panel_index')
openxlsx::writeData(w,'Slide_panel_index',idx)
openxlsx::freezePane(w,'Slide_panel_index',firstRow=TRUE)
openxlsx::setColWidths(w,'Slide_panel_index',1:9,14)
openxlsx::setColWidths(w,'Slide_panel_index',10:11,60)
openxlsx::addWorksheet(w,'Slide_summary')
openxlsx::writeData(w,'Slide_summary',idx[,.(panels=.N),by=.(slide,figure)])
openxlsx::saveWorkbook(w,file.path(out,'Slide_panel_index.xlsx'),overwrite=TRUE)

# Actual archive QA: editable DrawingML and text must exist on every slide;
# raster slide replacements are not allowed. Inspect numerical boundaries too.
extract <- tempfile('ppt_qa_');dir.create(extract)
utils::unzip(deck,exdir=extract)
ns <- c(p='http://schemas.openxmlformats.org/presentationml/2006/main',
        a='http://schemas.openxmlformats.org/drawingml/2006/main')
qa <- rbindlist(lapply(seq_along(selected),function(i) {
  slidefile <- file.path(extract,'ppt','slides',paste0('slide',i,'.xml'))
  xx <- xml2::read_xml(slidefile)
  groups <- xml2::xml_find_all(xx,'//p:grpSp/p:nvGrpSpPr/p:cNvPr',ns)
  expected_panels <- layouts[[selected[i]]]$panel
  stopifnot(length(groups)==length(expected_panels))
  for (j in seq_along(groups)) xml2::xml_set_attr(groups[[j]],'name',expected_panels[j])
  xml2::write_xml(xx,slidefile)
  txt <- xml2::xml_text(xml2::xml_find_all(xx,'//a:t',ns))
  shape_ids <- xml2::xml_attr(xml2::xml_find_all(xx,'//p:cNvPr',ns),'id')
  data.table(slide=i,figure=selected[i],
    native_shapes=length(xml2::xml_find_all(xx,'//p:sp',ns)),
    editable_text_runs=length(txt),
    raster_pictures=length(xml2::xml_find_all(xx,'//p:pic',ns)),
    editable_panel_groups=length(xml2::xml_find_all(xx,'//p:grpSp',ns)),
    duplicate_shape_ids=anyDuplicated(shape_ids),
    title_found=title_for(selected[i]) %in% txt,
    notes_present=file.exists(file.path(extract,'ppt','notesSlides',paste0('notesSlide',i,'.xml'))))
}))
stopifnot(all(qa$native_shapes>0),all(qa$editable_text_runs>0),
          all(qa$raster_pictures==0L),all(qa$title_found),all(qa$notes_present),
          all(qa$duplicate_shape_ids==0L),
          all(idx$left_mm>=0),all(idx$top_mm>=0),
          all(idx$left_mm+idx$width_mm<=W),all(idx$top_mm+idx$height_mm<=H))
if (!test) stopifnot(nrow(qa)==32L,nrow(idx)==117L,!anyDuplicated(idx$panel),setequal(idx$panel,all_ids))
# Name each native panel group for the PowerPoint Selection Pane.
zip::zipr(deck,files=list.files(extract,all.files=TRUE,no..=TRUE),root=extract)
after <- tools::md5sum(names(before));stopifnot(identical(before,after))
fwrite(qa,file.path(out,'qa','PPTX_archive_QA.tsv'),sep='\t')
warnings_out <- if(length(warning_log))rbindlist(warning_log,fill=TRUE) else
  data.table(figure=character(),panel=character(),message=character())
fwrite(warnings_out,file.path(out,'qa','render_warnings.tsv'),sep='\t')

# Contact sheets are rendered in R from the same slide previews, not screenshots
# generated by a different plotting backend. They verify composition rather than
# pretending to be an independent Microsoft PowerPoint rendering.
for (k in seq_len(ceiling(length(selected)/8))) {
  ids <- selected[seq.int((k-1)*8+1,min(k*8,length(selected)))]
  ragg::agg_png(file.path(out,'qa',sprintf('Contact_sheet_%02d.png',k)),
                width=2400,height=1850,res=160,background='#EEEEEE')
  grid::grid.newpage()
  for (j in seq_along(ids)) {
    col <- (j-1)%%4;row <- (j-1)%/%4
    img <- png::readPNG(file.path(out,'previews',paste0(ids[j],'.png')))
    grid::grid.raster(img,x=(col+.5)/4,y=1-(row+.5)/2,
                      width=grid::unit(.235,'npc'),height=grid::unit(.47,'npc'),interpolate=TRUE)
  }
  dev.off()
}
writeLines(c(capture.output(sessionInfo()),'',paste('PPTX:',basename(deck)),
             paste('Slides:',length(ppt)),paste('Panels:',nrow(idx)),
             paste('Archive QA:',if(all(qa$raster_pictures==0))'PASS - no slide/panel raster replacements'else'FAIL'),
             'Source analysis sentinel checksums: unchanged.',
             'Preview limitation: previews are R renders of the exact layouts; no native PowerPoint viewer was available.'),
           file.path(out,'qa','session_and_QA.txt'))
cat('PASS:',deck,'\nSlides:',length(ppt),'Panels:',nrow(idx),'\n')
