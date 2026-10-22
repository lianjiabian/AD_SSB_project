#!/usr/bin/env python3
"""Build gene-by-sample SSB count matrices from annotation BED intersections.

The current GRCh38 SSB pipeline writes gene IDs directly in gene/TSS BED files,
but exon/intron BED files contain transcript IDs.  This script parses the run's
GENCODE GTF, maps transcripts to genes, counts annotation rows per gene (the
same counting convention as the legacy ``cut | sort | uniq -c`` workflow), and
writes four complete matrices in sample-list order.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from array import array
from collections import Counter
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path


DEFAULT_RUN_ROOT = Path("/inputs/ssb_upstream")
DEFAULT_GTF = Path(
    "/inputs/reference/GRCh38.p14.R48_20250509/"
    "GRCh38.p14.v48.chr_patch_hapl_scaff.annotation.gtf"
)

KINDS = {
    "gene": ("6_Anno_Bed", 7, "SSB_readscount.tsv"),
    "exon": ("6_Exon_Anno_Bed", 3, "SSB_EXON_readscount.tsv"),
    "intron": ("6_Intron_Anno_Bed", 3, "SSB_INTRON_readscount.tsv"),
    "tss": ("6_Tss_Anno_Bed", 9, "SSB_TSS_readscount.tsv"),
}

TRANSCRIPT_TO_GENE: dict[str, str] = {}


def stable_id(value: str) -> str:
    return value.rstrip(";").split(".", 1)[0]


def parse_attrs(text: str) -> dict[str, str]:
    return dict(re.findall(r'(\S+) "([^"]+)"', text))


def load_gtf(gtf: Path):
    genes: dict[str, tuple[str, str]] = {}
    transcript_to_gene: dict[str, str] = {}
    with gtf.open() as handle:
        for line in handle:
            if not line or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 9:
                continue
            feature = fields[2]
            if feature not in {"gene", "transcript"}:
                continue
            attrs = parse_attrs(fields[8])
            gene_id = stable_id(attrs.get("gene_id", ""))
            if not gene_id:
                continue
            gene_name = attrs.get("gene_name", gene_id)
            gene_type = attrs.get("gene_type", "NA")
            if gene_name.startswith("MT-"):
                gene_type = "Mt_tRNA"
            genes.setdefault(gene_id, (gene_name, gene_type))
            if feature == "transcript" and attrs.get("transcript_id"):
                transcript_to_gene[stable_id(attrs["transcript_id"])] = gene_id
    if not genes or not transcript_to_gene:
        raise RuntimeError(f"Could not parse gene/transcript metadata from {gtf}")
    return genes, transcript_to_gene


def init_worker(transcript_to_gene):
    global TRANSCRIPT_TO_GENE
    TRANSCRIPT_TO_GENE = transcript_to_gene


def count_one(task):
    kind, sample, bed_path, key_col = task
    counts: Counter[str] = Counter()
    bad_rows = 0
    unmapped = 0
    with open(bed_path) as handle:
        for line in handle:
            fields = line.rstrip("\n").split("\t")
            if len(fields) <= key_col:
                bad_rows += 1
                continue
            feature_id = stable_id(fields[key_col])
            if kind in {"exon", "intron"}:
                gene_id = TRANSCRIPT_TO_GENE.get(feature_id)
                if gene_id is None:
                    unmapped += 1
                    continue
            else:
                gene_id = feature_id
            if gene_id:
                counts[gene_id] += 1
    return sample, counts, bad_rows, unmapped


def atomic_write_matrix(path: Path, samples, genes_meta, matrix):
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w") as out:
        out.write("gene_id\tgene_name\tgene_type\t" + "\t".join(samples) + "\n")
        for gene_id in sorted(matrix):
            gene_name, gene_type = genes_meta.get(gene_id, (gene_id, "NA"))
            values = "\t".join(map(str, matrix[gene_id]))
            out.write(f"{gene_id}\t{gene_name}\t{gene_type}\t{values}\n")
    os.replace(tmp, path)


def run_kind(kind, annotation_root, samples, genes_meta, transcript_to_gene, outdir, workers):
    dirname, key_col, output_name = KINDS[kind]
    source_dir = annotation_root / dirname
    missing = [s for s in samples if not (source_dir / f"{s}.anno.bed").is_file()]
    if missing:
        raise FileNotFoundError(f"{kind}: missing {len(missing)} files; first: {missing[:5]}")

    matrix: dict[str, array] = {}
    total_bad = 0
    total_unmapped = 0
    tasks = [
        (kind, sample, source_dir / f"{sample}.anno.bed", key_col)
        for sample in samples
    ]
    sample_index = {sample: i for i, sample in enumerate(samples)}
    with ProcessPoolExecutor(
        max_workers=workers,
        initializer=init_worker,
        initargs=(transcript_to_gene,),
    ) as pool:
        futures = [pool.submit(count_one, task) for task in tasks]
        completed = 0
        for future in as_completed(futures):
            sample, counts, bad_rows, unmapped = future.result()
            idx = sample_index[sample]
            for gene_id, value in counts.items():
                if gene_id not in matrix:
                    matrix[gene_id] = array("Q", [0]) * len(samples)
                matrix[gene_id][idx] = value
            total_bad += bad_rows
            total_unmapped += unmapped
            completed += 1
            if completed % 10 == 0 or completed == len(samples):
                print(f"[{kind}] {completed}/{len(samples)} samples", flush=True)

    output = outdir / output_name
    atomic_write_matrix(output, samples, genes_meta, matrix)
    print(
        f"[{kind}] wrote {output} ({len(matrix)} genes); "
        f"bad_rows={total_bad}, unmapped_transcript_rows={total_unmapped}",
        flush=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    parser.add_argument("--gtf", type=Path, default=DEFAULT_GTF)
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be at least 1")

    sample_list = args.run_root / "samples.txt"
    annotation_root = args.run_root / "ssb_run"
    samples = [x.strip() for x in sample_list.read_text().splitlines() if x.strip()]
    if len(samples) != len(set(samples)):
        raise RuntimeError("Duplicate sample IDs in sample list")
    print(f"Loaded {len(samples)} samples", flush=True)
    genes_meta, transcript_to_gene = load_gtf(args.gtf)
    print(
        f"Loaded {len(genes_meta)} genes and {len(transcript_to_gene)} transcripts from {args.gtf}",
        flush=True,
    )
    for kind in ("gene", "exon", "intron", "tss"):
        run_kind(
            kind, annotation_root, samples, genes_meta, transcript_to_gene,
            args.run_root, args.workers,
        )
    print("All four SSB count matrices completed", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr, flush=True)
        raise
