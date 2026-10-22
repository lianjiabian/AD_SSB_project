# Computational definitions

## Counting and annotation

Use the archived GRCh38.p14/GENCODE v48 reference bundle. GENE, EXON, INTRON and TSS200 intervals are merged within each gene, separately by chromosome. A deduplicated position can contribute at most once to the same gene/space. Different genes can share an event; both the per-gene sum and globally nonredundant class overlap are retained, and cross-gene shared intervals are excluded in a sensitivity analysis.

The original GENE/EXON/INTRON annotation coordinates are converted from one-based closed intervals by subtracting one from starts; ends are retained. Existing TSS200 windows are kept as their archived 401-bp windows. TSS200 is not silently redefined as upstream-only 200 bp. Exonic and intronic annotations can overlap across isoforms.

Deduplication uses chromosome, coordinate and strand. D includes all valid deduplicated positions in the complete BED, including non-genic regions and valid non-primary contigs; it is neither raw read count nor the gene-count sum.

## SSB_LPKM and Ri

For region r, gene i and participant j:

`LPKM[r,i,j] = C[r,i,j] × 10^10 / D[j]`

`Y[r,i,j] = log2(1 + LPKM[r,i,j])`

The historic name SSB_LPKM is retained with the explicit formula. No length division or TPM is performed, so this is not described as a per-kilobase break density. Region-union lengths remain available for bias and enrichment-background checks.

`B = sum_j sum_i C[GENE,i,j] / n`

`Ri[r,j] = sum_i C[r,i,j] / B`

B is fixed from the entire final cohort before detection filtering; all groups, subgroups, age strata and regions share it. Mean GENE Ri equals one by construction. Profile Ri uses exact transcript-bin accumulated integer counts divided by B. Profile totals are not required to equal GENE Ri because transcript/flank annotations and accumulation differ.

## Statistical framework

Main detection filtering requires nonzero observations in at least 20% of eligible participants; 10% and 30% are sensitivities. Separate tested sets are generated for predefined tasks. The main feature model is limma with empirical-Bayes inference:

`log2(1 + SSB_LPKM) ~ group + age + sex + log10(D) + polyA_retention`

The broad source task compares combined reviewed disease participants with HC. The pathology task compares the two pathology groups directly and with HC, using the same three-group feature set. BH correction is retained in full statistical tables; nominal plot P labels do not redefine the inferential threshold. Ri plots show every participant and descriptive comparisons, with adjusted regional models reported separately.

Models use five outer folds repeated five times and four inner folds. Filtering, imputation, technical processing, standardization, selection and tuning are fitted in their respective training partitions. Matched participants are blocked together. Participant-average held-out predictions and repetition-specific summaries have distinct meanings; their bootstrap uncertainty is not external validation.

Profile curves use 2,000 participant-level bootstrap draws. Transcript bins/genes are not independent patient replicates. Counts, mean-count curves and exposure-normalized density are named separately. Enrichment uses actually tested/mapped backgrounds and separates direction-specific sets, with 2,000 length-stratified draws for sensitivity.

## Public-release adaptations

Only paths, controlled participant-specific checks and the privacy-preserving sensitivity task label were adapted. The latter is named `exclude_discordant_record`. The authorized identifier is read through `SSB_DISCORDANT_SAMPLE_ID`, preserving exclusion—not reassignment—and the original seed-order position. No biological result was rerun or selected during publication packaging.
