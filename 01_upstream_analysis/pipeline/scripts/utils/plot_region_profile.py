#!/usr/bin/env python3
"""Render a simple SVG line plot from region_bin_mean_matrix.tsv."""

from __future__ import annotations

import argparse
import html
from pathlib import Path

REGION_ORDER = [
    "up5k_2k",
    "up2k_1k",
    "up1k_200",
    "up200_TSS",
    "first_exon",
    "first_intron",
    "internal_exons",
    "internal_introns",
    "last_exon",
    "down200_TES",
    "down1k_200",
    "down2k_1k",
    "down5k_2k",
]

COLORS = [
    "#2563eb",
    "#dc2626",
    "#16a34a",
    "#9333ea",
    "#ea580c",
    "#0891b2",
    "#be123c",
    "#4f46e5",
    "#65a30d",
    "#a16207",
    "#0f766e",
    "#7c3aed",
]


def read_matrix(path: str) -> tuple[list[tuple[str, str]], list[str], dict[str, list[float]]]:
    with open(path, "rt") as handle:
        header = handle.readline().rstrip("\n").split("\t")
        if len(header) < 3 or header[:2] != ["region", "bin"]:
            raise ValueError(f"{path}: expected header region, bin, sample...")
        samples = header[2:]
        keys: list[tuple[str, str]] = []
        values = {sample: [] for sample in samples}
        for line_no, line in enumerate(handle, 2):
            fields = line.rstrip("\n").split("\t")
            if len(fields) != len(header):
                raise ValueError(f"{path}:{line_no}: expected {len(header)} columns")
            region, bin_id = fields[:2]
            keys.append((region, bin_id))
            for sample, value in zip(samples, fields[2:]):
                values[sample].append(float(value))
    return keys, samples, values


def sort_rows(keys: list[tuple[str, str]], values: dict[str, list[float]]) -> tuple[list[tuple[str, str]], dict[str, list[float]]]:
    order = {region: idx for idx, region in enumerate(REGION_ORDER)}

    def key_fn(item: tuple[int, tuple[str, str]]) -> tuple[int, int]:
        _idx, (region, bin_id) = item
        return order.get(region, 999), int(bin_id)

    indexed = sorted(enumerate(keys), key=key_fn)
    new_keys = [key for _idx, key in indexed]
    new_values = {
        sample: [series[idx] for idx, _key in indexed]
        for sample, series in values.items()
    }
    return new_keys, new_values


def region_boundaries(keys: list[tuple[str, str]]) -> list[tuple[str, int, int]]:
    out: list[tuple[str, int, int]] = []
    if not keys:
        return out
    start = 0
    current = keys[0][0]
    for idx, (region, _bin_id) in enumerate(keys[1:], 1):
        if region != current:
            out.append((current, start, idx - 1))
            current = region
            start = idx
    out.append((current, start, len(keys) - 1))
    return out


def polyline(points: list[tuple[float, float]]) -> str:
    return " ".join(f"{x:.2f},{y:.2f}" for x, y in points)


def render_svg(
    keys: list[tuple[str, str]],
    samples: list[str],
    values: dict[str, list[float]],
    output_svg: str,
    width: int,
    height: int,
) -> None:
    margin_left = 90
    margin_right = 240 if samples else 40
    margin_top = 50
    margin_bottom = 130
    plot_w = max(100, width - margin_left - margin_right)
    plot_h = max(100, height - margin_top - margin_bottom)

    max_y = max((max(series) for series in values.values() if series), default=0.0)
    max_y = max_y if max_y > 0 else 1.0
    n = len(keys)
    x_step = plot_w / (n - 1) if n > 1 else plot_w

    def x_at(idx: int) -> float:
        return margin_left + idx * x_step

    def y_at(value: float) -> float:
        return margin_top + plot_h - (value / max_y) * plot_h

    svg: list[str] = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">')
    svg.append('<rect width="100%" height="100%" fill="#ffffff"/>')
    svg.append('<style>text{font-family:Arial,sans-serif;fill:#111827}.small{font-size:12px}.axis{stroke:#374151;stroke-width:1}.grid{stroke:#e5e7eb;stroke-width:1}.label{font-size:11px;fill:#374151}</style>')
    svg.append(f'<text x="{margin_left}" y="28" font-size="20" font-weight="700">SSB gene-region profile</text>')

    for tick in range(6):
        value = max_y * tick / 5
        y = y_at(value)
        svg.append(f'<line class="grid" x1="{margin_left}" y1="{y:.2f}" x2="{margin_left + plot_w}" y2="{y:.2f}"/>')
        svg.append(f'<text class="small" x="{margin_left - 12}" y="{y + 4:.2f}" text-anchor="end">{value:.3g}</text>')

    svg.append(f'<line class="axis" x1="{margin_left}" y1="{margin_top + plot_h}" x2="{margin_left + plot_w}" y2="{margin_top + plot_h}"/>')
    svg.append(f'<line class="axis" x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{margin_top + plot_h}"/>')

    for region, start, end in region_boundaries(keys):
        x1 = x_at(start)
        x2 = x_at(end)
        xc = (x1 + x2) / 2
        svg.append(f'<line class="grid" x1="{x1:.2f}" y1="{margin_top}" x2="{x1:.2f}" y2="{margin_top + plot_h}"/>')
        svg.append(f'<text class="label" transform="translate({xc:.2f},{margin_top + plot_h + 18}) rotate(45)" text-anchor="start">{html.escape(region)}</text>')
    if keys:
        x_last = x_at(len(keys) - 1)
        svg.append(f'<line class="grid" x1="{x_last:.2f}" y1="{margin_top}" x2="{x_last:.2f}" y2="{margin_top + plot_h}"/>')

    for idx, sample in enumerate(samples):
        color = COLORS[idx % len(COLORS)]
        points = [(x_at(i), y_at(v)) for i, v in enumerate(values[sample])]
        svg.append(f'<polyline fill="none" stroke="{color}" stroke-width="2" points="{polyline(points)}"/>')
        for x, y in points:
            svg.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="2" fill="{color}"/>')

        lx = margin_left + plot_w + 28
        ly = margin_top + 22 + idx * 22
        if ly < height - 20:
            svg.append(f'<line x1="{lx}" y1="{ly - 4}" x2="{lx + 20}" y2="{ly - 4}" stroke="{color}" stroke-width="3"/>')
            svg.append(f'<text class="small" x="{lx + 28}" y="{ly}">{html.escape(sample)}</text>')

    svg.append(f'<text class="small" x="{margin_left + plot_w / 2:.2f}" y="{height - 18}" text-anchor="middle">Transcript-oriented gene regions</text>')
    svg.append(f'<text class="small" transform="translate(22,{margin_top + plot_h / 2:.2f}) rotate(-90)" text-anchor="middle">Mean SSB count</text>')
    svg.append("</svg>")

    out = Path(output_svg)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(svg) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", required=True, help="region_bin_mean_matrix.tsv")
    parser.add_argument("--output-svg", required=True, help="Output SVG path")
    parser.add_argument("--width", type=int, default=1400, help="SVG width")
    parser.add_argument("--height", type=int, default=700, help="SVG height")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    keys, samples, values = read_matrix(args.matrix)
    keys, values = sort_rows(keys, values)
    render_svg(keys, samples, values, args.output_svg, args.width, args.height)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
