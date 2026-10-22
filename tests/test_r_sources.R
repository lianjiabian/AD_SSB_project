# Data-free source syntax checks. Run from repository root, or pass it as arg 1.
args<-commandArgs(TRUE);root<-normalizePath(if(length(args))args[1]else'.')
ff<-list.files(root,full.names=TRUE,recursive=TRUE,all.files=TRUE,no..=TRUE)
ff<-ff[!grepl('/([.]git|work|__pycache__)/',ff)]
r<-ff[grepl('[.]R$',ff)]
for(f in r)tryCatch(parse(f),error=function(e)stop('R syntax: ',f,': ',conditionMessage(e)))
sh<-ff[grepl('[.]sh$',ff)]
for(f in sh)stopifnot(system2('bash',c('-n',shQuote(f)))==0L)
cat('PASS R parse:',length(r),'files; Bash syntax:',length(sh),'files\n')
