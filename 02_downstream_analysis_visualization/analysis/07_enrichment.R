source('code/00_config.R');suppressPackageStartupMessages({library(httr);library(jsonlite)})
space<-Sys.getenv('SSB_ENRICHMENT_SPACE',unset=PRIMARY_SPACE)
stopifnot(space%in%SPACES)
outdir<-if(space==PRIMARY_SPACE)'results/enrichment'else paste0('results/enrichment/',space,'_sensitivity')
dir.create(path(outdir),recursive=TRUE,showWarnings=FALSE)
enpath<-function(...)path(outdir,...)
# All transport, analysis and exports are implemented in R as requested.
post<-function(endpoint,form,key){raw<-enpath(paste0(key,'.json'));if(file.exists(raw))return(as.data.table(fromJSON(raw)));form$species<-9606;form$caller_identity<-'SSB_QC261_20261013';write_json(list(endpoint=endpoint,form=form),enpath(paste0(key,'_request.json')),auto_unbox=TRUE,pretty=TRUE)
 for(attempt in 1:3){res<-try(POST(paste0('https://string-db.org/api/json/',endpoint),body=form,encode='form',timeout(120)),silent=TRUE);if(!inherits(res,'try-error')&&status_code(res)==200)break;if(!inherits(res,'try-error')&&endpoint=='get_string_ids'&&status_code(res)==404&&grepl('nothing found',content(res,as='text',encoding='UTF-8'),fixed=TRUE)){writeLines('[]',raw);writeLines(content(res,as='text',encoding='UTF-8'),path('audit',paste0(key,'_no_protein_mapping.json')));return(data.table())};if(attempt<3)Sys.sleep(2)}
 if(inherits(res,'try-error')||status_code(res)!=200)stop('STRING API request failed: ',key)
 txt<-content(res,as='text',encoding='UTF-8');writeLines(txt,raw);Sys.sleep(.4);as.data.table(fromJSON(txt))
}
v<-post('version',list(),'version');wr(v,enpath('database_version.tsv'))
a<-rd(path('results/differential',paste0(space,'__A_primary__Disease_vs_HC.tsv')));a[,stable_id:=sub('\\..*$','',gene_id)];chunks<-split(seq_len(nrow(a)),ceiling(seq_len(nrow(a))/1000));maps<-list()
for(i in seq_along(chunks)){ii<-chunks[[i]];q<-a$stable_id[ii];z<-post('get_string_ids',list(identifiers=paste(q,collapse='\r'),limit=1,echo_query=1),sprintf('mapping_%03d',i));if(nrow(z)){z[,gene_id:=a$gene_id[ii[as.integer(queryIndex)+1L]]];maps[[i]]<-z};cat('STRING mapping',i,'/',length(chunks),'\n')}
mapping<-rbindlist(maps,fill=TRUE);wr(mapping,enpath('tested_mapping.tsv'));universe<-unique(mapping$stringId);stopifnot(length(universe)>0)
b<-rd(path('results/differential',paste0(space,'__B_primary__Positive_vs_Negative.tsv')));sets<-list(All=a[FDR<.05],Higher=a[FDR<.05&beta>0],Lower=a[FDR<.05&beta<0]);if(uniqueN(mapping[gene_id%in%b[FDR<.05,gene_id],stringId])>=20)sets$Pathology<-b[FDR<.05]
ans<-manifest<-list();for(n in names(sets)){q<-unique(mapping[gene_id%in%sets[[n]]$gene_id,stringId]);if(length(q)<2){manifest[[n]]<-data.table(set=n,query_genes=nrow(sets[[n]]),query_proteins=length(q),background=length(universe),status='Fewer than two mapped proteins');next};z<-post('enrichment',list(identifiers=paste(q,collapse='\r'),background_string_identifiers=paste(universe,collapse='\r')),paste0('enrichment_',n));if(nrow(z)){for(j in names(z))if(is.list(z[[j]]))set(z,j=j,value=vapply(z[[j]],paste,character(1),collapse=';'));z[,`:=`(set=n,query_proteins=length(q),background_proteins=length(universe))];ans[[n]]<-z};manifest[[n]]<-data.table(set=n,query_genes=nrow(sets[[n]]),query_proteins=length(q),background=length(universe),status='PASS',returned_terms=nrow(z))}
all<-rbindlist(ans,fill=TRUE);if(!nrow(all)){all<-data.table(set=character(),category=character(),term=character(),description=character(),p_value=numeric(),fdr=numeric(),number_of_genes=integer(),inputGenes=character())}
all[,provider_category:=category];all[category=='HPO'&!grepl('^HP:',term),category:='Other phenotype ontology'];wr(all,enpath('all_terms.tsv'));wr(rbindlist(manifest,fill=TRUE),enpath('set_manifest.tsv'))
top<-all[category%in%c('Process','Component','RCTM','HPO')&fdr<.05][order(fdr,term),head(.SD,5),by=.(set,category)];wr(top,enpath('top5.tsv'))
# Length-stratified resampling of the detected mapped background for displayed terms.
# Uses new within-gene union length; no length division is applied to LPKM.
aa<-merge(a[,.(gene_id,region_length_bp,FDR)],mapping[,.(gene_id,stringId)],by='gene_id');aa<-aa[,.(length_bp=as.numeric(median(region_length_bp)),associated=any(FDR<.05)),by=stringId];breaks<-unique(quantile(log1p(aa$length_bp),seq(0,1,.1)));aa[,stratum:=cut(log1p(length_bp),breaks,include.lowest=TRUE,labels=FALSE)]
terms<-all[set=='All' & category%in%c('Process','Component','RCTM','HPO')]
if(nrow(terms)){
 # Provider inputGenes lists query hits, not the full term membership. Obtain the
 # version-matched human annotations to form a valid length-matched null universe.
 suppressPackageStartupMessages(library(Matrix));ver<-v$string_version[1]
 f<-path('reference',paste0('9606.protein.enrichment.terms.v',ver,'.txt.gz'))
 url<-paste0('https://stringdb-downloads.org/download/protein.enrichment.terms.v',ver,'/9606.protein.enrichment.terms.v',ver,'.txt.gz')
 if(!file.exists(f))download.file(url,f,mode='wb',quiet=TRUE,method='libcurl')
 # The download and current API use slightly different phenotype evidence subsets.
 # Query the same API's complete annotations for the tested universe, in batches,
 # so query-hit and null-set term memberships use exactly the enrichment evidence.
 batches<-split(aa$stringId,ceiling(seq_len(nrow(aa))/1000));annlist<-list()
 for(j in seq_along(batches)){z<-post('functional_annotation',list(identifiers=paste(batches[[j]],collapse='\r'),allow_pubmed=0),sprintf('universe_annotations_%02d',j));z<-z[term%in%terms$term];annlist[[j]]<-rbindlist(lapply(seq_len(nrow(z)),function(i)data.table(stringId=as.character(z$inputGenes[[i]]),term=z$term[i])));cat('Full term membership',j,'/',length(batches),'\n')}
 ann<-unique(rbindlist(annlist))
 levels<-unique(terms$term);inc<-sparseMatrix(i=match(ann$stringId,aa$stringId),j=match(ann$term,levels),x=1,dims=c(nrow(aa),length(levels)))
 set.seed(SEED);strata<-split(seq_len(nrow(aa)),aa$stratum);draws<-replicate(2000,unlist(lapply(strata,function(ii){n<-sum(aa$associated[ii]);if(n)ii[sample.int(length(ii),n,replace=FALSE)]else integer()})),simplify=FALSE)
 drawmat<-sparseMatrix(i=unlist(draws),j=rep(seq_along(draws),lengths(draws)),x=1,dims=c(nrow(aa),2000))
 null<-as.matrix(crossprod(inc,drawmat));obs<-as.numeric(crossprod(inc,as.numeric(aa$associated)));bgcount<-as.numeric(colSums(inc))
 p<-data.table(term=levels,observed_overlap=obs,background_members=bgcount,permutations=2000,length_stratified_P=(1+rowSums(null>=obs))/2001)
 p<-merge(terms[,.(term,category,description,provider_observed=number_of_genes)],p,by='term');p[,length_stratified_FDR:=p.adjust(length_stratified_P,'BH')]
 wr(p,enpath('length_stratified_sensitivity.tsv'));wr(data.table(space=space,source='https://string-db.org/api/json/functional_annotation',version=ver,comparison_download=url,comparison_download_md5=unname(tools::md5sum(f)),terms=nrow(p),observed_membership_disagreements=sum(p$observed_overlap!=p$provider_observed)),path('audit',paste0(space,'_enrichment_full_membership_validation.tsv')))
 stopifnot(all(p$observed_overlap==p$provider_observed))
}else wr(data.table(term=character(),length_stratified_P=numeric(),length_stratified_FDR=numeric()),enpath('length_stratified_sensitivity.tsv'))
logstage('enrichment',paste('PASS new',space,'queries, detected mapped background and length-stratified sensitivity'))
