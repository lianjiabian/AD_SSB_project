# Downstream analysis and visualization

The main entry point is `bash run.sh STAGE`. Without `--execute`, computational stages only print a plan. `check` performs read-only dependency/input checks. The actual study inputs are restricted and are not downloaded by this code.

Stages: `prepare`, `quantify`, `statistics`, `base-figures`, `presentation`, `latest-figures`, `all`.

- `analysis/01_clinical.R`: manual review, approved final cohort, observed clinical records and actual analysis n. Participant-specific assertions are read from a controlled external table.
- `analysis/02_rebuild_counts.R`: within-gene annotation union, full-library D, count/LPKM/Ri and unshared sensitivities.
- `analysis/02a_reference_audit.R`: independent reference-union and profile-input audit.
- `analysis/03_statistics.R`: regional and feature comparisons, age/matching/blood-cell/detection/shared-interval sensitivities.
- `analysis/04_models.R`: independent regional models, five outer folds repeated five times, four inner folds, fold-specific preprocessing and held-out predictions.
- `analysis/05a_profile_from_BED.R`, `05_profile.R`: exact integer transcript-bin reconstruction, shared-denominator profile Ri, participant bootstrap and tests.
- `analysis/06_clinical_QC261.R`: observed Table 1, missingness, MMSE/other clinical associations and exploratory stage summaries.
- `analysis/07_enrichment.R`: tested/mapped background, direction-specific sets and length-stratified sensitivity.
- `analysis/08*`: plot definitions and per-panel source data; the `panels/` scripts are thin single-panel entry points.
- `analysis/09*`, `11*`–`14*`: reporting templates, workbooks, audit manifests and private/public output separation.
- `analysis/96*`, `97*`, `10*`: synthetic algebra, dependencies and complete-analysis QA.
- `presentation/R/`: approved submission numbering, panels, composites, Word and native PPT.
- `native_powerpoint/`: baseline editable DrawingML generation.
- `revisions/`: latest display-only revisions and their checks.

All archived study-wide sample counts and some reporting text are fixed to the reviewed study. This is not a general-purpose cohort-adjudication application. If data change, use a new output directory and re-evaluate every assertion, statistical output and manuscript sentence.

The direct sensitivity model uses `SSB_DISCORDANT_SAMPLE_ID`, not a public literal participant identifier. Its task key is `exclude_discordant_record`. This key was renamed for privacy; model formula, fold-seed ordering and exclusion behavior with the authorized setting are unchanged.

See [the full reproduction guide](../docs/REPRODUCIBILITY.md), [inputs](../docs/INPUTS.md), [methods](../docs/METHODS.md) and [figure map](../PANEL_CODE_MAPPING.tsv).
