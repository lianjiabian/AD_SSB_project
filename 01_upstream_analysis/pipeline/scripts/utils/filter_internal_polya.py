#!/usr/bin/env python3
"""Remove candidate SSB breaks likely caused by internal polyA priming."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable, TextIO

RC_TABLE = str.maketrans("ACGTNacgtn", "TGCANtgcan")


class FastaAccessor:
    def __init__(self, fasta_path: str | Path) -> None:
        self.path = str(fasta_path)
        self._fasta = None
        self._genome: dict[str, str] | None = None
        try:
            from pyfaidx import Fasta

            self._fasta = Fasta(self.path, sequence_always_upper=True)
        except ImportError:
            print(
                "WARNING: pyfaidx is not installed; loading the whole FASTA into memory.",
                file=sys.stderr,
            )
            self._genome = self._load_fasta(self.path)

    @staticmethod
    def _load_fasta(path: str) -> dict[str, str]:
        genome: dict[str, list[str]] = {}
        chrom = ""
        with open(path, "rt") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                if line.startswith(">"):
                    chrom = line[1:].split()[0]
                    genome[chrom] = []
                elif chrom:
                    genome[chrom].append(line.upper())
        return {key: "".join(value) for key, value in genome.items()}

    def fetch(self, chrom: str, start: int, end: int) -> str:
        start = max(0, start)
        if end <= start:
            return ""
        if self._fasta is not None:
            if chrom not in self._fasta:
                raise KeyError(chrom)
            return str(self._fasta[chrom][start:end]).upper()
        assert self._genome is not None
        if chrom not in self._genome:
            raise KeyError(chrom)
        return self._genome[chrom][start:end].upper()


def reverse_complement(seq: str) -> str:
    return seq.translate(RC_TABLE)[::-1].upper()


def parse_bed(path: str | Path) -> Iterable[tuple[str, int, int, str, str, str]]:
    with open(path, "rt") as handle:
        for line_no, line in enumerate(handle, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 6:
                raise ValueError(f"{path}:{line_no}: expected at least 6 BED columns")
            chrom, start, end, read_id, score, strand = fields[:6]
            yield chrom, int(start), int(end), read_id, score, strand


def open_output(path: str | None) -> TextIO:
    if path:
        return open(path, "wt")
    return sys.stdout


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-bed", required=True, help="Candidate break BED")
    parser.add_argument("--genome-fasta", required=True, help="Reference genome FASTA")
    parser.add_argument("--output-bed", help="Filtered BED output; stdout if omitted")
    parser.add_argument("--window", type=int, default=40, help="Sequence window length [40]")
    parser.add_argument(
        "--max-t-ratio",
        type=float,
        default=0.4,
        help="Keep records with T ratio below this cutoff [0.4]",
    )
    parser.add_argument(
        "--legacy-minus-offset",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Use the old minus-strand downstream offset of end+1 [default: true]",
    )
    parser.add_argument("--stats", help="Write JSON filtering statistics")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    fasta = FastaAccessor(args.genome_fasta)

    total = kept = missing_chrom = 0
    with open_output(args.output_bed) as out:
        for chrom, start, end, read_id, _score, strand in parse_bed(args.input_bed):
            total += 1
            if end < start:
                start, end = end, start
            try:
                if strand == "+":
                    seq = fasta.fetch(chrom, start - args.window, start)
                elif strand == "-":
                    offset = 1 if args.legacy_minus_offset else 0
                    seq = reverse_complement(fasta.fetch(chrom, end + offset, end + offset + args.window))
                else:
                    continue
            except KeyError:
                missing_chrom += 1
                continue

            t_ratio = seq.count("T") / args.window if args.window else 0.0
            if t_ratio < args.max_t_ratio:
                kept += 1
                out.write(f"{chrom}\t{start}\t{end}\t{read_id}\t{t_ratio:.2f}\t{strand}\n")

    stats = {
        "records_total": total,
        "records_kept": kept,
        "records_removed": total - kept,
        "missing_chrom_records": missing_chrom,
        "window": args.window,
        "max_t_ratio": args.max_t_ratio,
        "legacy_minus_offset": args.legacy_minus_offset,
    }
    if args.stats:
        Path(args.stats).write_text(json.dumps(stats, indent=2) + "\n")
    else:
        print(json.dumps(stats, indent=2), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
