#!/usr/bin/env python3
"""Filter paired FASTQ reads by SSB flag motifs and trim at the motif edge."""

from __future__ import annotations

import argparse
import gzip
import json
import re
import sys
from pathlib import Path
from typing import Iterator, TextIO


def open_text(path: str | Path, mode: str) -> TextIO:
    path = Path(path)
    if path.suffix == ".gz":
        if "w" in mode:
            return gzip.open(path, mode, compresslevel=5)  # type: ignore[return-value]
        return gzip.open(path, mode)  # type: ignore[return-value]
    return path.open(mode)


def read_fastq(handle: TextIO, name: str) -> Iterator[tuple[str, str, str, str]]:
    line_no = 0
    while True:
        header = handle.readline()
        if not header:
            return
        seq = handle.readline()
        plus = handle.readline()
        qual = handle.readline()
        line_no += 4
        if not seq or not plus or not qual:
            raise ValueError(f"{name}: incomplete FASTQ record ending near line {line_no}")
        record = (
            header.rstrip("\r\n"),
            seq.rstrip("\r\n"),
            plus.rstrip("\r\n"),
            qual.rstrip("\r\n"),
        )
        if not record[0].startswith("@"):
            raise ValueError(f"{name}: invalid FASTQ header near line {line_no - 3}")
        if not record[2].startswith("+"):
            raise ValueError(f"{name}: invalid FASTQ plus line near line {line_no - 1}")
        if len(record[1]) != len(record[3]):
            raise ValueError(
                f"{name}: sequence/quality length mismatch near line {line_no}"
            )
        yield record


def normalized_read_id(header: str) -> str:
    """Return the mate-independent read id used for strict PE validation."""
    token = header[1:].split(maxsplit=1)[0]
    return re.sub(r"/[12]$", "", token)


def write_record(handle: TextIO, record: tuple[str, str, str, str]) -> None:
    handle.write("\n".join(record))
    handle.write("\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Filter paired FASTQ reads by R1/R2 SSB flag motifs."
    )
    parser.add_argument("--r1", required=True, help="R1 FASTQ, optionally gzipped")
    parser.add_argument("--r2", required=True, help="R2 FASTQ, optionally gzipped")
    parser.add_argument("--out-r1", required=True, help="Filtered R1 FASTQ")
    parser.add_argument("--out-r2", required=True, help="Filtered R2 FASTQ")
    parser.add_argument("--flag-r1", required=True, help="Literal R1 flag motif")
    parser.add_argument("--flag-r2", required=True, help="Literal R2 flag motif")
    parser.add_argument(
        "--anchor-r1",
        default="[ATC]",
        help="Regex immediately following the R1 flag; legacy default keeps the anchor base",
    )
    parser.add_argument(
        "--anchor-r2",
        default="[AGC]",
        help="Regex immediately following the R2 flag; legacy default keeps the anchor base",
    )
    parser.add_argument("--min-length", type=int, default=1, help="Minimum trimmed read length")
    parser.add_argument("--stats", help="Write JSON filtering statistics")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    pattern_r1 = re.compile(re.escape(args.flag_r1) + args.anchor_r1)
    pattern_r2 = re.compile(re.escape(args.flag_r2) + args.anchor_r2)

    total = kept = too_short = 0

    with (
        open_text(args.r1, "rt") as in_r1,
        open_text(args.r2, "rt") as in_r2,
        open_text(args.out_r1, "wt") as out_r1,
        open_text(args.out_r2, "wt") as out_r2,
    ):
        iter_r1 = read_fastq(in_r1, args.r1)
        iter_r2 = read_fastq(in_r2, args.r2)
        while True:
            rec1 = next(iter_r1, None)
            rec2 = next(iter_r2, None)
            if rec1 is None and rec2 is None:
                break
            if rec1 is None or rec2 is None:
                raise ValueError("R1 and R2 contain different numbers of FASTQ records")

            if normalized_read_id(rec1[0]) != normalized_read_id(rec2[0]):
                raise ValueError(
                    "R1/R2 read identifiers are not paired: "
                    f"{rec1[0]!r} versus {rec2[0]!r}"
                )

            total += 1
            m1 = pattern_r1.search(rec1[1])
            m2 = pattern_r2.search(rec2[1])
            if not m1 or not m2:
                continue

            cut1 = m1.end() - 1
            cut2 = m2.end() - 1
            seq1 = rec1[1][cut1:]
            seq2 = rec2[1][cut2:]
            qual1 = rec1[3][cut1:]
            qual2 = rec2[3][cut2:]
            if len(seq1) < args.min_length or len(seq2) < args.min_length:
                too_short += 1
                continue

            write_record(out_r1, (rec1[0], seq1, rec1[2], qual1))
            write_record(out_r2, (rec2[0], seq2, rec2[2], qual2))
            kept += 1

    stats = {
        "read_pairs_total": total,
        "read_pairs_kept": kept,
        "read_pairs_removed": total - kept,
        "read_pairs_too_short_after_trim": too_short,
        "kept_fraction": kept / total if total else 0.0,
    }

    if args.stats:
        Path(args.stats).write_text(json.dumps(stats, indent=2) + "\n")
    else:
        print(json.dumps(stats, indent=2), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
