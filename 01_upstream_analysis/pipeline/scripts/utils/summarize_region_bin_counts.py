#!/usr/bin/env python3
"""Summarize bedtools region-bin counts into transcript and mean profile tables."""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path

REGION_ORDER = {
    "up5k_2k": 1,
    "up2k_1k": 2,
    "up1k_200": 3,
    "up200_TSS": 4,
    "first_exon": 5,
    "first_intron": 6,
    "internal_exons": 7,
    "internal_introns": 8,
    "last_exon": 9,
    "down200_TES": 10,
    "down1k_200": 11,
    "down2k_1k": 12,
    "down5k_2k": 13,
}


def region_key(region: str, bin_id: str) -> tuple[int, int, str]:
    try:
        bin_int = int(bin_id)
    except ValueError:
        bin_int = 0
    return REGION_ORDER.get(region, 99), bin_int, region


def summarize_counts(counts_bed: str, sample: str, out_transcript: str, out_mean: str) -> None:
    transcript_counts: dict[tuple[str, str, str, str, str], int] = defaultdict(int)
    with open(counts_bed, "rt") as handle:
        for line_no, line in enumerate(handle, 1):
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 9:
                raise ValueError(f"{counts_bed}:{line_no}: expected at least 9 columns")
            tx_id, gene_id, strand, region, bin_id = fields[3], fields[4], fields[5], fields[6], fields[7]
            count = int(fields[-1])
            transcript_counts[(tx_id, gene_id, strand, region, bin_id)] += count

    Path(out_transcript).parent.mkdir(parents=True, exist_ok=True)
    with open(out_transcript, "wt") as out:
        out.write("sample\ttranscript_id\tgene_id\tstrand\tregion\tbin\tcount\n")
        for key, count in sorted(transcript_counts.items(), key=lambda item: (item[0][0], region_key(item[0][3], item[0][4]))):
            tx_id, gene_id, strand, region, bin_id = key
            out.write(f"{sample}\t{tx_id}\t{gene_id}\t{strand}\t{region}\t{bin_id}\t{count}\n")

    sums: dict[tuple[str, str], int] = defaultdict(int)
    sizes: dict[tuple[str, str], int] = defaultdict(int)
    for (_tx_id, _gene_id, _strand, region, bin_id), count in transcript_counts.items():
        key = (region, bin_id)
        sums[key] += count
        sizes[key] += 1

    with open(out_mean, "wt") as out:
        out.write("sample\tregion\tbin\tmean_count\ttranscript_bins\n")
        for region, bin_id in sorted(sums, key=lambda key: region_key(key[0], key[1])):
            mean = sums[(region, bin_id)] / sizes[(region, bin_id)] if sizes[(region, bin_id)] else 0.0
            out.write(f"{sample}\t{region}\t{bin_id}\t{mean:.6g}\t{sizes[(region, bin_id)]}\n")


def merge_means(mean_files: list[str], out_matrix: str) -> None:
    values: dict[tuple[str, str], dict[str, str]] = defaultdict(dict)
    samples: list[str] = []
    for path in mean_files:
        with open(path, "rt") as handle:
            header = handle.readline().rstrip("\n").split("\t")
            if header[:4] != ["sample", "region", "bin", "mean_count"]:
                raise ValueError(f"{path}: unexpected mean table header")
            for line in handle:
                sample, region, bin_id, mean_count, *_rest = line.rstrip("\n").split("\t")
                if sample not in samples:
                    samples.append(sample)
                values[(region, bin_id)][sample] = mean_count

    Path(out_matrix).parent.mkdir(parents=True, exist_ok=True)
    with open(out_matrix, "wt") as out:
        out.write("region\tbin\t" + "\t".join(samples) + "\n")
        for region, bin_id in sorted(values, key=lambda key: region_key(key[0], key[1])):
            row = [values[(region, bin_id)].get(sample, "0") for sample in samples]
            out.write(f"{region}\t{bin_id}\t" + "\t".join(row) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--counts-bed", help="bedtools -wa -c output for one sample")
    parser.add_argument("--sample", help="Sample id for --counts-bed mode")
    parser.add_argument("--out-transcript", help="Transcript-bin count table")
    parser.add_argument("--out-mean", help="Mean region-bin profile table")
    parser.add_argument("--mean-files", nargs="*", help="Mean tables to merge")
    parser.add_argument("--out-matrix", help="Merged mean-count matrix")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.counts_bed:
        missing = [
            name
            for name in ("sample", "out_transcript", "out_mean")
            if getattr(args, name) is None
        ]
        if missing:
            raise SystemExit(f"Missing required arguments for --counts-bed mode: {', '.join(missing)}")
        summarize_counts(args.counts_bed, args.sample, args.out_transcript, args.out_mean)
    if args.mean_files:
        if not args.out_matrix:
            raise SystemExit("--out-matrix is required with --mean-files")
        merge_means(args.mean_files, args.out_matrix)
    if not args.counts_bed and not args.mean_files:
        raise SystemExit("Provide --counts-bed or --mean-files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
