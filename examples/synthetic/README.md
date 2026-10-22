# Synthetic metric demonstration

Every identifier starts with `SYN`; all numbers are invented for algebra tests. No participant groups, MMSE values or real sequencing results are represented. Do not combine these rows with clinical data or cite them as a study result.

`counts.tsv`: four illustrative feature spaces, three synthetic gene keys, six invented samples. `library_totals.tsv`: synthetic full-library D values. Counts are integers; D is positive; failed libraries are not simulated as zeros.

Run `Rscript examples/synthetic/run_metrics.R` from the repository root. The example verifies count/D scaling, valid zero handling, separate log-signal, the common unfiltered GENE denominator and mean GENE Ri of one. It prints results but creates no analysis-output directory.
