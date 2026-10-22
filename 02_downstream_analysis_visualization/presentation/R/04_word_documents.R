source('R/00_common.R')
suppressPackageStartupMessages({library(officer);library(xml2)})
xe<-function(s){s<-gsub('&','&amp;',s,fixed=TRUE);s<-gsub('<','&lt;',s,fixed=TRUE);gsub('>','&gt;',s,fixed=TRUE)}
mr<-function(s)paste0('<m:r><m:rPr><m:sty m:val="p"/></m:rPr><m:t>',xe(s),'</m:t></m:r>')
subm<-function(a,b)paste0('<m:sSub><m:e>',mr(a),'</m:e><m:sub>',mr(b),'</m:sub></m:sSub>')
supm<-function(a,b)paste0('<m:sSup><m:e>',mr(a),'</m:e><m:sup>',mr(b),'</m:sup></m:sSup>')
subsup<-function(a,b,c)paste0('<m:sSubSup><m:e>',mr(a),'</m:e><m:sub>',mr(b),'</m:sub><m:sup>',mr(c),'</m:sup></m:sSubSup>')
frac<-function(a,b)paste0('<m:f><m:num>',a,'</m:num><m:den>',b,'</m:den></m:f>')
sumxml<-function(k,e)paste0('<m:nary><m:naryPr><m:chr m:val="∑"/><m:limLoc m:val="undOvr"/><m:supHide m:val="1"/></m:naryPr><m:sub>',mr(k),'</m:sub><m:sup/><m:e>',e,'</m:e></m:nary>')
math_inline<-function(s){bs<-intToUtf8(92);v<-if(identical(s,'R_{ij}'))subm('R','ij')else if(identical(s,'D_j'))subm('D','j')else if(identical(s,'B'))mr('B')else if(grepl('log',s,fixed=TRUE)){if(grepl('10',s,fixed=TRUE))subm('log','10')else paste0(subm('log','2'),mr('(1 + SSB_LPKM)'))}else{ss<-gsub(paste0(bs,'mathrm'),' ',s,fixed=TRUE);ss<-gsub(bs,'',ss,fixed=TRUE);ss<-gsub('{','',ss,fixed=TRUE);ss<-gsub('}','',ss,fixed=TRUE);mr(ss)};paste0('<m:oMath>',v,'</m:oMath>')}
rich_runs<-function(s){
  n<-nchar(s);i<-1L;bold<-FALSE;italic<-FALSE;buf<-'';out<-character();bs<-intToUtf8(92)
  flush<-function(){if(nzchar(buf)){out<<-c(out,paste0('<w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Microsoft YaHei"/><w:sz w:val="22"/>',if(bold)'<w:b/>'else'',if(italic)'<w:i/>'else'','</w:rPr><w:t xml:space="preserve">',xe(buf),'</w:t></w:r>'));buf<<-''}}
  while(i<=n){
    if(substr(s,i,i+1L)=='**'){flush();bold<-!bold;i<-i+2L;next}
    if(substr(s,i,i)=='*'){flush();italic<-!italic;i<-i+1L;next}
    if(substr(s,i,i+1L)==paste0(bs,'(')){
      tail<-substr(s,i+2L,n);j<-regexpr(paste0(bs,')'),tail,fixed=TRUE)[1]
      if(j>0){flush();out<-c(out,math_inline(substr(tail,1,j-1)));i<-i+2L+j+1L;next}
    }
    buf<-paste0(buf,substr(s,i,i));i<-i+1L
  };flush();paste(out,collapse='')
}
word_from_md<-function(file,out){
  lines<-readLines(file,warn=FALSE);doc<-read_docx();doc<-body_set_default_section(doc,prop_section(page_size=page_size(width=8.27,height=11.69),page_margins=page_mar(top=.85,bottom=.85,left=.9,right=.9)))
  equation<-FALSE;eq<-character();math_count<-0L;bs<-intToUtf8(92)
  for(line in lines){
    if(identical(line,paste0(bs,'['))){equation<-TRUE;eq<-character();next}
    if(equation){
      if(identical(line,paste0(bs,']'))){
        math_count<-math_count+1L
        form<-if(math_count==1L)paste0(subm('SSB_LPKM','ij'),mr(' = '),frac(paste0(subm('R','ij'),mr(' × '),supm('10','10')),subm('D','j')))else paste0(subm('Ri','rj'),mr(' = '),frac(sumxml('i',subsup('R','ij','(r)')),mr('B')),mr(' ,     B = '),frac(mr('1'),mr('N')),sumxml('j',sumxml('i',subsup('R','ij','(GENE)'))))
        doc<-body_add_xml(doc,paste0('<w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"><m:oMathPara><m:oMath>',form,'</m:oMath></m:oMathPara></w:p>'));equation<-FALSE;next
      }else{eq<-c(eq,line);next}
    }
    if(!nzchar(trimws(line)))next
    if(startsWith(line,'### ')){doc<-body_add_fpar(doc,fpar(ftext(substring(line,5),fp_text(font.family='Arial',font.size=12,bold=TRUE,color='000000'))),style='heading 2');next}
    if(startsWith(line,'## ')){doc<-body_add_fpar(doc,fpar(ftext(substring(line,4),fp_text(font.family='Arial',font.size=14,bold=TRUE,color='000000'))),style='heading 1');next}
    if(startsWith(line,'# ')){doc<-body_add_fpar(doc,fpar(ftext(substring(line,3),fp_text(font.family='Arial',font.size=16,bold=TRUE))));next}
    pp<-paste0('<w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"><w:pPr><w:spacing w:after="120" w:line="330" w:lineRule="auto"/><w:widowControl/></w:pPr>',rich_runs(line),'</w:p>')
    doc<-body_add_xml(doc,pp)
  }
  stopifnot(!equation);print(doc,target=out);invisible(math_count)
}
for(nm in c('Manuscript_SSB_revised_full_EN_renumbered','Figure_legends_EN_renumbered','Supplementary_Information'))word_from_md(P('manuscript',paste0(nm,'.md')),P('manuscript',paste0(nm,'.docx')))
# Update table headers, but preserve every original data-row cell verbatim.
f<-P('tables/Table_1.docx');td<-tempfile('table1_');dir.create(td);unzip(f,exdir=td);xf<-file.path(td,'word/document.xml');x<-read_xml(xf);ns<-xml_ns(x)
rows<-xml_find_all(x,'//w:tbl/w:tr',ns);original_values<-vapply(rows[-1],xml_text,character(1))
tt<-xml_find_all(rows[[1]],'.//w:t',ns)
for(j in seq_along(tt)){s<-xml_text(tt[[j]]);if(s=='AD (n=89)')xml_set_text(tt[[j]],'Core 1-positive AD pathology (n=89)');if(s=='Other (n=28)')xml_set_text(tt[[j]],'Core 1-negative cognitive disorders (n=28)')}
stopifnot(identical(original_values,vapply(xml_find_all(x,'//w:tbl/w:tr',ns)[-1],xml_text,character(1))))
write_xml(x,xf);zip::zipr(f,files=list.files(td,all.files=TRUE,no..=TRUE),root=td)
wr(data.table(check='Every Table 1 data-row cell unchanged',PASS=TRUE),P('mapping_and_QC/Table1_value_preservation.tsv'))
checklist<-c('# Author completion checklist','',
'The manuscript follows the author-revised scientific narrative and retains the supplied study population, results and references. Figure and supplementary numbering have been synchronized.',
'Before journal submission, complete author names, affiliations, corresponding-author details, funding, CRediT roles and acknowledgements. Confirm the competing-interest statement as indicated in the manuscript.',
'Confirm the provided ethics/waiver statement, biomarker-platform thresholds, recruitment and laboratory-processing details against institutional source records. This reorganization does not independently certify those records.',
'Add authorized repository/access identifiers and the code version after institutional approval. No external upload has been performed.',
'Reference wording and numbering were preserved as supplied; reference verification or journal-specific reference resequencing was not part of this task.',
'Figures are editable vector PDF/SVG/PPT; companion TIFFs are 600 dpi. Individual coded source data and clinical workbooks require access and consent review before any public release.')
writeLines(checklist,P('manuscript/Author_completion_checklist.md'));word_from_md(P('manuscript/Author_completion_checklist.md'),P('manuscript/Author_completion_checklist.docx'))
cover<-c('# Cover letter','', 'Dear Editor,','',
'Please consider our manuscript, “A peripheral-blood single-strand DNA break atlas across cognitive disorders and Alzheimer pathology”, as a Research Article.',
'We present a nucleotide-resolution peripheral-blood SSB atlas linked to reviewed clinical and Core 1 biomarker records in 261 participants. The primary EXON analysis identifies 360 adjusted associations, while complementary whole-gene and transcript-structure analyses place these signals in a broader genomic context.',
'The manuscript separates cognitive-disease association from Core 1 pathology discrimination and evaluates independent molecular models using repeated nested cross-validation. This design defines what the SSB landscape captures alongside established AD biomarkers.',
'Editable main and supplementary figures, a comprehensive supplementary workbook, figure-source data and reproducible R code accompany the manuscript.',
'[Authors to complete: editor/journal, corresponding-author details, exclusive-submission and originality confirmations, author approval, disclosures and authorized data/code access information.]','', 'Sincerely,','[Corresponding author]')
writeLines(cover,P('manuscript/Cover_letter.md'));word_from_md(P('manuscript/Cover_letter.md'),P('manuscript/Cover_letter.docx'))
cat('WORD PASS: complete manuscript, legends, supplementary information and unchanged-value Table 1.\n')
