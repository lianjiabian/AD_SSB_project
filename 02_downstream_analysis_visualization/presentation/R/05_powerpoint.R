# Reuse existing editable DrawingML only at unchanged physical dimensions.
# Resized or subset panels are rendered from the preserved R plot objects.
source('R/00_common.R')
suppressPackageStartupMessages({library(officer);library(xml2);library(rvg)})
reg<-readRDS(P('mapping_and_QC/figure_registry.rds'));legs<-readRDS(P('mapping_and_QC/legends.rds'))
oldppt<-P('source_panels/Original_editable_figures.pptx');if(!file.exists(oldppt))oldppt<-file.path(BASE,'FINAL_SUBMISSION_PACKAGE/PowerPoint/SSB_All_Figures_editable_20261015.pptx')
indexfile<-P('source_panels/Original_PPT_panel_index.tsv');if(!file.exists(indexfile))indexfile<-file.path(BASE,'PPT_assembly_20261015/Slide_panel_index.tsv');oldidx<-rd(indexfile)
oldDir<-tempfile('old_native_');dir.create(oldDir);unzip(oldppt,exdir=oldDir)
template<-P('source_panels/portrait_template.pptx');if(!file.exists(template))template<-file.path(BASE,'PPT_assembly_20261015/qa/portrait_template.pptx')
ns<-c(p='http://schemas.openxmlformats.org/presentationml/2006/main',a='http://schemas.openxmlformats.org/drawingml/2006/main',r='http://schemas.openxmlformats.org/officeDocument/2006/relationships')
EMU<-function(mm)as.character(round(mm*36000))
titlefor<-function(fig)if(startsWith(fig,'S'))paste('Supplementary Figure',fig)else sub('Figure','Figure ',fig)
plain<-function(x)gsub('**','',x,fixed=TRUE)
skeletal<-function(figs,file){
  d<-read_pptx(template);while(length(d))d<-remove_slide(d,index=length(d))
  for(fig in figs){d<-add_slide(d,layout='Blank',master='Office Theme');d<-ph_with(d,fpar(ftext(titlefor(fig),fp_text(font.family='Arial',font.size=12,bold=TRUE))),location=ph_location(left=8.5/25.4,top=3/25.4,width=183/25.4,height=8/25.4));leg<-if(startsWith(fig,'S'))paste(titlefor(fig),reg$titles[[fig]],plain(legs$supplementary[[fig]]))else plain(legs$main[[fig]]);d<-set_notes(d,value=leg,location=notes_location_type(type='body'))};print(d,target=file)
}
figs<-names(reg$layouts)
skel<-P('mapping_and_QC/native_skeleton.pptx');skeletal(figs,skel)
build<-tempfile('new_native_');dir.create(build);unzip(skel,exdir=build)
reuse_audit<-list();slide_audit<-list()
for(i in seq_along(figs)){
  fig<-figs[i];cat('NATIVE',fig,'\n');flush.console()
  sf<-file.path(build,'ppt/slides',paste0('slide',i,'.xml'));x<-read_xml(sf);tree<-xml_find_first(x,'/p:sld/p:cSld/p:spTree',ns);lay<-reg$layouts[[fig]]
  cache<-new.env(parent=emptyenv())
  for(j in seq_len(nrow(lay))){
    b<-lay[j];old<-oldidx[panel==b$old_id];stopifnot(nrow(old)==1)
    reuse<-!nzchar(b$subset)&&abs(old$width_mm-b$width_mm)<.001&&abs(old$height_mm-b$height_mm)<.001&&!b$new_id%in%c('FigS20A','FigS20B')
    cat('  PANEL',b$new_id,'source',b$old_id,'reuse',reuse,'\n');flush.console()
    left<-b$left_mm+8.5;top<-b$top_mm+15
    if(reuse){
      key<-as.character(old$slide)
      if(!exists(key,cache,inherits=FALSE))assign(key,read_xml(file.path(oldDir,'ppt/slides',paste0('slide',key,'.xml'))),cache)
      ox<-get(key,cache);gp<-xml_find_first(ox,paste0('//p:grpSp[p:nvGrpSpPr/p:cNvPr[@name="',b$old_id,'"]]'),ns)
      stopifnot(!inherits(gp,'xml_missing'))
      node<-xml_add_child(tree,gp,.copy=TRUE)
      off<-xml_find_first(node,'./p:grpSpPr/a:xfrm/a:off',ns)
      xml_set_attr(off,'x',EMU(left));xml_set_attr(off,'y',EMU(top))
      oldtag<-old$tag
      tt<-xml_find_all(node,'.//a:t',ns);which_tag<-which(xml_text(tt)==oldtag)
      stopifnot(length(which_tag)>0);xml_set_text(tt[[tail(which_tag,1)]],b$tag)
    }else{
      tmp<-tempfile('native_panel_',fileext='.xml');p<-load_panel(b$new_id,8.5)
      rvg::dml_pptx(file=tmp,width=b$width_mm/25.4,height=b$height_mm/25.4,
                    offx=left/25.4,offy=top/25.4,bg='white',editable=TRUE,standalone=FALSE)
      tryCatch(draw_panel(p,b$tag),finally=dev.off())
      raw<-readLines(tmp,warn=FALSE);raw<-sub('<[?]xml[^>]*[?]>','',raw,perl=TRUE)
      wrapper<-paste0('<root xmlns:p="',ns['p'],'" xmlns:a="',ns['a'],'" xmlns:r="',ns['r'],'">',paste(raw,collapse=''),' </root>')
      wx<-read_xml(wrapper);gp<-xml_find_first(wx,'.//p:grpSp',ns);if(inherits(gp,'xml_missing'))stop('Missing generated native group: ',b$new_id,'; XML: ',substr(paste(raw,collapse=''),1,200));node<-xml_add_child(tree,gp,.copy=TRUE)
    }
    xml_set_attr(xml_find_first(node,'./p:nvGrpSpPr/p:cNvPr',ns),'name',b$new_id)
    # Pure translations preserve all vertex coordinates and font sizes.
    if(reuse){
      p0<-xml_find_all(gp,'.//a:pathLst',ns);p1<-xml_find_all(node,'.//a:pathLst',ns)
      geometry_ok<-identical(vapply(p0,as.character,character(1)),vapply(p1,as.character,character(1)))
      sizes_ok<-identical(xml_attr(xml_find_all(gp,'.//a:rPr',ns),'sz'),xml_attr(xml_find_all(node,'.//a:rPr',ns),'sz'))
      stopifnot(geometry_ok,sizes_ok)
    }else{geometry_ok<-TRUE;sizes_ok<-TRUE}
    reuse_audit[[length(reuse_audit)+1L]]<-data.table(figure=fig,panel=b$new_id,source=b$old_id,mode=if(reuse)'native vector reuse; translation only'else'R vector render; no statistical computation',geometry_preserved=geometry_ok,font_sizes_preserved=sizes_ok)
  }
  ids<-xml_find_all(x,'//p:cNvPr',ns);xml_set_attr(ids,'id',as.character(seq_along(ids)))
  xml_write<-write_xml(x,sf)
  groups<-xml_find_all(x,'//p:grpSp/p:nvGrpSpPr/p:cNvPr',ns)
  sa<-data.table(figure=fig,panels=length(groups),native_shapes=length(xml_find_all(x,'//p:sp',ns)),raster_pictures=length(xml_find_all(x,'//p:pic',ns)),editable_text_runs=length(xml_find_all(x,'//a:t',ns)),duplicate_ids=anyDuplicated(xml_attr(ids,'id')))
  stopifnot(sa$panels==nrow(lay),sa$raster_pictures==0L,sa$duplicate_ids==0L,setequal(xml_attr(groups,'name'),lay$new_id))
  slide_audit[[i]]<-sa;rm(cache,x);gc(verbose=FALSE)
}
outfile<-P('powerpoint/All_figures_editable.pptx')
zip::zipr(outfile,files=list.files(build,all.files=TRUE,no..=TRUE),root=build)
# Small dedicated decks keep their own notes, slide relationships and order.
for(kind in c('main','supplementary')){
  ff<-figs[if(kind=='main')!startsWith(figs,'S')else startsWith(figs,'S')]
  subfile<-P(paste0(kind,'_figures'),paste0(if(kind=='main')'Main'else'Supplementary','_figures_editable.pptx'))
  skeletal(ff,subfile);subdir<-tempfile('native_subset_');dir.create(subdir);unzip(subfile,exdir=subdir)
  for(k in seq_along(ff)){src<-file.path(build,'ppt/slides',paste0('slide',match(ff[k],figs),'.xml'));dst<-file.path(subdir,'ppt/slides',paste0('slide',k,'.xml'));stopifnot(file.copy(src,dst,overwrite=TRUE))}
  zip::zipr(subfile,files=list.files(subdir,all.files=TRUE,no..=TRUE),root=subdir)
}
ra<-rbindlist(reuse_audit);sa<-rbindlist(slide_audit)
stopifnot(nrow(sa)==29L,sum(sa$panels)==107L,!anyDuplicated(ra$panel))
wr(ra,P('mapping_and_QC/PowerPoint_vector_lineage.tsv'));wr(sa,P('mapping_and_QC/PowerPoint_structure_QA.tsv'))
cat('POWERPOINT PASS: 29 slides, 107 editable panel groups, no raster panel replacements.\n')
