source('code/00_config.R');suppressPackageStartupMessages({library(httr);library(jsonlite);library(xml2)})
dir.create(path('manuscript/reference_evidence'),recursive=TRUE,showWarnings=FALSE)
dois<-c('10.1038/s41467-019-13602-7','10.1111/acel.14122','10.1002/alz.13859','10.1016/j.jalz.2011.03.005','10.1093/nar/gkv007','10.1111/j.2517-6161.1995.tb02031.x','10.18637/jss.v033.i01','10.1093/nar/gkac1000','10.1136/bmj-2023-078378')
out<-list()
for(i in seq_along(dois)){
 u<-'https://www.ebi.ac.uk/europepmc/webservices/rest/search';r<-try(GET(u,query=list(query=paste0('DOI:"',dois[i],'"'),format='json'),timeout(30)),silent=TRUE)
 if(inherits(r,'try-error')||status_code(r)!=200){out[[i]]<-data.table(reference=i,doi=dois[i],verification='Network unavailable; verify DOI with publisher before submission');next}
 txt<-content(r,'text',encoding='UTF-8');writeLines(txt,path('manuscript/reference_evidence',paste0('ref_',i,'.json')));z<-fromJSON(txt)$resultList$result
 if(is.null(z)||!is.data.frame(z)||nrow(z)==0){out[[i]]<-data.table(reference=i,doi=dois[i],verification='Not indexed in Europe PMC; publisher DOI retained');next}
 out[[i]]<-data.table(reference=i,doi=dois[i],title=z$title[1],authors=z$authorString[1],year=z$pubYear[1],journal=z$journalTitle[1],volume=z$journalVolume[1],pages=z$pageInfo[1],pmid=z$id[1],verification='Europe PMC primary bibliographic record verified')
}
wr(rbindlist(out,fill=TRUE),path('manuscript/References_verified.tsv'));savebook(list(References=rbindlist(out,fill=TRUE)),path('manuscript/References_verified.xlsx'))
for(id in c('PMC11113270','PMC6925131')){r<-try(GET(paste0('https://www.ebi.ac.uk/europepmc/webservices/rest/',id,'/fullTextXML'),timeout(30)),silent=TRUE);if(inherits(r,'try-error')||status_code(r)!=200)next;txt<-content(r,'text',encoding='UTF-8');writeLines(txt,path('manuscript/reference_evidence',paste0(id,'.xml')));doc<-read_xml(txt);ps<-xml_text(xml_find_all(doc,'.//p'));sel<-ps[grepl('LPKM|normalized|normalization|genic|Ri|R_i',ps,ignore.case=TRUE)];writeLines(sel,path('manuscript/reference_evidence',paste0(id,'_metric_passages.txt')))}
logstage('references','PASS bibliography provenance recorded; publisher-only items flagged')
