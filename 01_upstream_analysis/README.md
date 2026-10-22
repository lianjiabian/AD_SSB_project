# Upstream analysis

Run `run_upstream.sh --plan` or, explicitly, `--execute`. Provide an authorized one-ID-per-line sample list using `SSB_SAMPLE_LIST`. No true sample list is included in this repository. Set FASTQ, reference, environment and output paths in an external configuration; `../config/local.env.example.sh` is a non-identifying example.

The retained processing sequence is paired-read flag filtering, BWA alignment, MAPQ filtering, break-end extraction, internal poly(A) filtering, deduplication and annotation. Defaults are BWA, MAPQ 20, R1 flag `GGGGGGGGGG`, R2 flag `TTTTTTTTTTTT`, internal filtering window 40 and T-ratio cutoff 0.4. Review `pipeline/scripts/pipeline/ssb_pipeline.sh` for the exact SAM flags and strand-end transformation. Same chromosome, one-base interval and strand define deduplicated events.

The final deduplicated BED, rather than transcript-cumulative annotation output, is the input to downstream nonredundant gene counting. Profiling retains the original 13-region/150-bin transcript structure.

## Environment and resources

- `pipeline/environment.conda-explicit.txt`: recorded Linux Conda package URLs.
- `pipeline/environment.pip-freeze.txt`: recorded pip packages; inspect rather than blindly install a full mixed-environment freeze.
- `pipeline/environment.yml`: broad environment specification; optional packages listed there need not have been present in the archived run.
- `pipeline/tool_versions.tsv`: observed upstream tool versions, with portable example paths.
- `pipeline/resource_manifest.tsv`: reference bundle provenance; reference files are not redistributed.

Activate the recreated environment or set `SSB_ENV_PREFIX`. A valid GRCh38.p14/GENCODE v48 reference bundle and its BWA index must be supplied separately. Example roots are placeholders, not downloadable resources. Do not run an old environment validation script as proof that a new server has the original inputs.

## Resource settings

The archived launch used one sample at a time, 30 threads per command and 30 profile processes. BWA, samtools view and sort can run concurrently, so that was not a hard 30-thread process limit. The portable wrapper defaults to nine threads per pipeline command and 30 profile processes, preserving algorithms while reducing concurrent CPU demand. Use `SSB_THREADS_PER_COMMAND=30` to request the archived per-command setting. Enforce a hard budget with an external scheduler/cgroup if needed.

The upstream wrapper is independent of the final clinical subset: its authorized list may contain all original sequenced samples, while downstream clinical inclusion is fixed separately. The original launch contained 306 samples; no public file reveals their identities.

## Legacy conversion scripts

`legacy_count_merge/` preserves BED-annotation-to-TSV conversion and its synthetic tests. It intentionally reproduces historical annotation multiplicity. Do not use its summed exon rows as the final within-gene nonredundant EXON counts; the R reconstruction in `analysis/02_rebuild_counts.R` is authoritative for those.
