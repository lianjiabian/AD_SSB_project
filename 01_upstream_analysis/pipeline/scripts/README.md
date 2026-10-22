# Script Layout

## Active Scripts

### Root

- `run_all.sh`: one-command full workflow from paired FASTQs through breakpoint calling, profile matrix generation, and SVG profile plotting.

### `pipeline/`

- `ssb_pipeline.sh`: main SSB breakpoint workflow from paired FASTQ to deduplicated break BED and optional annotation.

### `profile/`

- `ssb_profiling_plot_pre.sh`: build transcript-oriented gene-region bins from GTF.
- `ssb_profile.sh`: count sample breakpoints over region bins and build the plot-ready matrix.

### `utils/`

- `filter_paired_flags.py`: pair-safe SSB flag filtering and trimming.
- `filter_internal_polya.py`: internal polyA priming filter.
- `make_gene_region_bins.py`: GTF to transcript-region bins.
- `summarize_region_bin_counts.py`: summarize raw bin counts into profile tables.
- `plot_region_profile.py`: render a quick-look SVG profile plot from the merged matrix.
- `check_env.sh`: local environment preflight.

## Legacy Scripts

`legacy/` contains pre-refactor draft scripts retained for reference. They are not used by the active workflow.
