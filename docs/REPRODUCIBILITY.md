# Reproduction guide

## Levels of reproduction

1. **Public, data-free checks:** parse code and exercise metric identities on synthetic arrays. These run without patient files or analysis packages.
2. **Authorized scientific recomputation:** rebuild counts from deduplicated BED, fit statistical/prediction models, recreate source tables and figures. This requires the controlled clinical inputs and original references.
3. **Authorized display replay:** recreate approved layouts using preserved R plots and statistical tables. This is not a rerun of inference.

The package was prepared and checked locally. No remote workflow, repository publication, external validation or new participant-data computation is claimed by those checks.

## Environment

The archived R runtime was 4.5.3. `02_downstream_analysis_visualization/environment/package_version_lock.tsv` records key versions; `current_R_packages.tsv` records observed package versions without workstation library paths. These are version records, **not** a complete tested cross-platform dependency lock. For strict recreation, preserve the original runtime/library snapshot and compare package versions before fitting. A fresh install of current packages is not guaranteed to reproduce every numeric result.

R packages include data.table, matrixStats, IRanges, S4Vectors, limma, glmnet, Matrix, ggplot2, patchwork, svglite, ragg, openxlsx, officer, rvg, flextable, xml2, httr, jsonlite, stringr, png, zip and systemfonts. Arial must be installed with appropriate font rights. Native graphics need Cairo/fontconfig support. PDF/TIFF checks use Poppler and ImageMagick. External commands used for decoding/checking do not replace the R statistical implementations.

GitHub CI uses [checkout](https://github.com/actions/checkout) and [setup-r](https://github.com/r-lib/actions/tree/v2/setup-r) to run data-free checks. It does not install or validate the complete clinical analysis environment.

## Configuration and inputs

Copy `config/local.env.example.sh` outside the repository, replace example roots, set the authorized discordant-record identifier and the path to the private review-check table, then source that file. Never commit it. The public sample-list filename and sample-specific sensitivity values are intentionally unset.

The authorized analysis input directory must retain the input layout in `INPUTS.md`. This prevents an old clinical label file from silently replacing the reviewed final cohort. The final grouping list is authoritative alongside the reviewed CSV, not diagnosis text alone.

## Commands

```bash
source /absolute/path/to/my-private-settings.sh
bash 02_downstream_analysis_visualization/run.sh check

bash 02_downstream_analysis_visualization/run.sh prepare --execute --out=/work/new_ssb_run
bash 02_downstream_analysis_visualization/run.sh quantify --execute --out=/work/new_ssb_run
bash 02_downstream_analysis_visualization/run.sh statistics --execute --out=/work/new_ssb_run
bash 02_downstream_analysis_visualization/run.sh base-figures --execute --out=/work/new_ssb_run
bash 02_downstream_analysis_visualization/run.sh presentation --execute --out=/work/new_ssb_run \
  --analysis-root=/work/new_ssb_run/analysis
bash 02_downstream_analysis_visualization/run.sh latest-figures --execute --out=/work/new_ssb_run \
  --analysis-root=/work/new_ssb_run/analysis --presentation-root=/work/new_ssb_run/presentation
```

Alternatively, `all --execute --out=/work/new_ssb_run` performs that chain. The entry point refuses protected/unknown nonempty output roots. Do not reuse checkpoints after changing inputs, annotations, filter settings or clinical labels. Use a new output root.

`quantify` generates fresh profile integers before the reference audit verifies those files; it does not substitute rounded profile means for integer counts. `statistics` can be long-running and includes repeated nested model fitting and enrichment requests. Stage logs are generated under the new output root.

## Display-only replay

```bash
bash 02_downstream_analysis_visualization/run.sh latest-figures --execute --out=/work/new_layout_replay
```

This uses the configured approved presentation as an external input, copying its figure objects and source tables to a new work directory. It can require GB-scale disk space even though this repository is small. The final output index is `LATEST_OUTPUTS.txt`; `Figure4_previous` is an intermediate QA reference, not the final Figure 4.

The S18 revision expects the archived vector/raster export structure. It changes figure legends, not participant data or model values. It does not by itself edit existing PPT slides; no unsupported claim of updated native S18 PPT is made.

## Single panels

From a populated analysis working root, run `Rscript code/panels/<panel>.R`. From a populated presentation root, run `Rscript R/panels/<panel>.R`. `PANEL_CODE_MAPPING.tsv` links current submission panels to analysis panels. The final composite revisions are applied after the baseline presentation render.

## Numeric reproducibility and online resources

Compare participant identities/order, complete-case n, input BED hashes, annotation coordinate audit, GENE denominator B, matrices, tested features, coefficients, folds and held-out predictions with the archived analysis. Do not use a preferred P value or AUC direction as a success criterion.

The STRING API can change. Strictly replaying enrichment requires the original database version and request/response archives whose query and background exactly match recomputed sets. The entry point does not copy old inference outputs and label them new computations; a fresh run may access the live endpoint. Record and explain any database drift. Bibliographic verification can also use the network and saves its evidence separately.

Reporting scripts contain archived aggregate result text. Check every number, direction and panel citation after a fresh analysis before using generated manuscripts for submission.
