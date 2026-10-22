# Synthetic algebra checks only. These are NOT participant data or findings.
C<-matrix(c(0,3,8,2,5,0),nrow=2,dimnames=list(c('toy_gene1','toy_gene2'),c('toy1','toy2','toy3')));D<-c(10,20,30)
L<-sweep(C,2,D,'/')*1e10;B<-mean(colSums(C));Ri<-colSums(C)/B
stopifnot(all(C<=rep(D,each=nrow(C))),all(L==sweep(C,2,D,'/')*1e10),mean(Ri)==1,L[1,1]==0,all(is.finite(log2(1+L))))
E<-C/2;stopifnot(all(colSums(E)/B==Ri/2))
cat('PASS: synthetic LPKM, shared GENE Ri denominator, zero and log-signal algebra\n')
