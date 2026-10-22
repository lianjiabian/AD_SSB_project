#!/usr/bin/env python3
"""Build transcript-oriented region bins for SSB metagene/profile plots."""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

REGION_NBINS = {
    "up5k_2k": 10,
    "up2k_1k": 10,
    "up1k_200": 10,
    "up200_TSS": 10,
    "first_exon": 10,
    "first_intron": 20,
    "internal_exons": 10,
    "internal_introns": 20,
    "last_exon": 10,
    "down200_TES": 10,
    "down1k_200": 10,
    "down2k_1k": 10,
    "down5k_2k": 10,
}

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


@dataclass
class Transcript:
    chrom: str
    tx_id: str
    gene_id: str
    strand: str
    tx_type: str = "."
    exons: list[tuple[int, int]] = field(default_factory=list)


def parse_attributes(raw: str) -> dict[str, str]:
    attrs: dict[str, str] = {}
    for item in raw.strip().rstrip(";").split(";"):
        item = item.strip()
        if not item:
            continue
        if " " in item:
            key, value = item.split(" ", 1)
            attrs[key] = value.strip().strip('"')
        elif "=" in item:
            key, value = item.split("=", 1)
            attrs[key] = value.strip().strip('"')
    return attrs


def read_gtf(path: str | Path, transcript_types: set[str] | None) -> dict[str, Transcript]:
    transcripts: dict[str, Transcript] = {}
    with open(path, "rt") as handle:
        for line_no, line in enumerate(handle, 1):
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 9:
                raise ValueError(f"{path}:{line_no}: expected 9 GTF columns")
            chrom, _source, feature, start, end, _score, strand, _frame, attr_raw = fields
            if feature != "exon":
                continue
            attrs = parse_attributes(attr_raw)
            tx_id = attrs.get("transcript_id")
            gene_id = attrs.get("gene_id", attrs.get("gene_name", "."))
            tx_type = attrs.get("transcript_type", attrs.get("transcript_biotype", "."))
            if not tx_id:
                continue
            if transcript_types and tx_type not in transcript_types:
                continue
            if strand not in {"+", "-"}:
                continue
            tx = transcripts.get(tx_id)
            if tx is None:
                tx = Transcript(chrom=chrom, tx_id=tx_id, gene_id=gene_id, strand=strand, tx_type=tx_type)
                transcripts[tx_id] = tx
            tx.exons.append((int(start) - 1, int(end)))
    return transcripts


def clamp_interval(start: int, end: int) -> tuple[int, int] | None:
    start = max(0, start)
    end = max(0, end)
    if end <= start:
        return None
    return start, end


def split_segments(
    segments: list[tuple[int, int]],
    nbin: int,
    strand: str,
) -> Iterable[tuple[int, int, int]]:
    clean = [(start, end) for start, end in segments if end > start]
    total = sum(end - start for start, end in clean)
    if total < nbin:
        return

    offsets: list[tuple[int, int, int]] = []
    cursor = 0
    for start, end in clean:
        length = end - start
        offsets.append((cursor, start, end))
        cursor += length

    for bin_idx in range(nbin):
        bin_start = int(bin_idx * total / nbin)
        bin_end = total if bin_idx == nbin - 1 else int((bin_idx + 1) * total / nbin)
        if bin_end <= bin_start:
            continue
        for seg_offset, seg_start, seg_end in offsets:
            seg_len = seg_end - seg_start
            overlap_start = max(bin_start, seg_offset)
            overlap_end = min(bin_end, seg_offset + seg_len)
            if overlap_end <= overlap_start:
                continue
            left = overlap_start - seg_offset
            right = overlap_end - seg_offset
            if strand == "+":
                bed_start = seg_start + left
                bed_end = seg_start + right
            else:
                bed_start = seg_end - right
                bed_end = seg_end - left
            if bed_end > bed_start:
                yield bed_start, bed_end, bin_idx + 1


def gap_between(a: tuple[int, int], b: tuple[int, int]) -> tuple[int, int] | None:
    if a[0] <= b[0]:
        start, end = a[1], b[0]
    else:
        start, end = b[1], a[0]
    return clamp_interval(start, end)


def add_region(
    rows: list[tuple[str, int, int, str, str, str, str, int]],
    tx: Transcript,
    region: str,
    segments: list[tuple[int, int]],
) -> None:
    nbin = REGION_NBINS[region]
    for start, end, bin_idx in split_segments(segments, nbin, tx.strand):
        rows.append((tx.chrom, start, end, tx.tx_id, tx.gene_id, tx.strand, region, bin_idx))


def build_rows(transcripts: dict[str, Transcript]) -> list[tuple[str, int, int, str, str, str, str, int]]:
    rows: list[tuple[str, int, int, str, str, str, str, int]] = []

    for tx in transcripts.values():
        if not tx.exons:
            continue
        exons_asc = sorted(set(tx.exons))
        exons = exons_asc if tx.strand == "+" else list(reversed(exons_asc))
        first = exons[0]
        last = exons[-1]

        if tx.strand == "+":
            tss = first[0]
            tes = last[1]
            flank_segments = {
                "up5k_2k": clamp_interval(tss - 5000, tss - 2000),
                "up2k_1k": clamp_interval(tss - 2000, tss - 1000),
                "up1k_200": clamp_interval(tss - 1000, tss - 200),
                "up200_TSS": clamp_interval(tss - 200, tss),
                "down200_TES": clamp_interval(tes, tes + 200),
                "down1k_200": clamp_interval(tes + 200, tes + 1000),
                "down2k_1k": clamp_interval(tes + 1000, tes + 2000),
                "down5k_2k": clamp_interval(tes + 2000, tes + 5000),
            }
        else:
            tss = first[1]
            tes = last[0]
            flank_segments = {
                "up5k_2k": clamp_interval(tss + 2000, tss + 5000),
                "up2k_1k": clamp_interval(tss + 1000, tss + 2000),
                "up1k_200": clamp_interval(tss + 200, tss + 1000),
                "up200_TSS": clamp_interval(tss, tss + 200),
                "down200_TES": clamp_interval(tes - 200, tes),
                "down1k_200": clamp_interval(tes - 1000, tes - 200),
                "down2k_1k": clamp_interval(tes - 2000, tes - 1000),
                "down5k_2k": clamp_interval(tes - 5000, tes - 2000),
            }

        for region, segment in flank_segments.items():
            if segment:
                add_region(rows, tx, region, [segment])

        add_region(rows, tx, "first_exon", [first])
        add_region(rows, tx, "last_exon", [last])

        if len(exons) > 2:
            add_region(rows, tx, "internal_exons", exons[1:-1])

        introns = [gap for gap in (gap_between(a, b) for a, b in zip(exons, exons[1:])) if gap]
        if introns:
            add_region(rows, tx, "first_intron", [introns[0]])
        if len(introns) > 1:
            add_region(rows, tx, "internal_introns", introns[1:])

    rows.sort(key=lambda r: (r[0], r[1], r[2], r[3], REGION_ORDER.get(r[6], 99), r[7]))
    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gtf", required=True, help="Input GTF annotation")
    parser.add_argument("--output-bins", required=True, help="Output BED with region bins")
    parser.add_argument(
        "--transcript-types",
        help="Comma-separated transcript_type/biotype values to keep; default keeps all",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tx_types = set(args.transcript_types.split(",")) if args.transcript_types else None
    transcripts = read_gtf(args.gtf, tx_types)
    rows = build_rows(transcripts)

    out = Path(args.output_bins)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("wt") as handle:
        for row in rows:
            handle.write("\t".join(map(str, row)) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
