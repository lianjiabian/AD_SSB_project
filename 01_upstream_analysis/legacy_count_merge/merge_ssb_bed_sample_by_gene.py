#!/usr/bin/env python3
"""Count original annotation BED rows into sample-by-gene-symbol TSVs.

No QC subset, normalization, or breakpoint deduplication is applied. Transcript
annotation overlaps retain their multiplicity. Python standard library only.
"""
import argparse
import csv
import hashlib
import json
import os
import platform
import re
import time
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

KINDS = {
    'GENE': ('6_Anno_Bed', 14, 7),
    'EXON': ('6_Exon_Anno_Bed', 11, 3),
    'TSS': ('6_Tss_Anno_Bed', 16, 9),
    'INTRON': ('6_Intron_Anno_Bed', 12, 3),
}
TRANSCRIPTS = {}


def natural_key(text):
    return tuple(int(x) if x.isdigit() else x for x in re.split(r'(\d+)', text))


def stable(identifier):
    return re.sub(rb'\.\d+(?=_|$)', b'', identifier.rstrip(b';'))


def load_mapping(path):
    tx = {}
    aliases = defaultdict(set)
    genes = defaultdict(set)
    with path.open('rb') as handle:
        for n, line in enumerate(handle, 1):
            f = line.rstrip(b'\r\n').split(b'\t')
            if len(f) != 5:
                raise ValueError(f'{path}:{n}: expected 5 mapping columns')
            transcript, _, gid, symbol, _ = f
            if not symbol or symbol == b'.':
                symbol = stable(gid)
            if transcript in tx and tx[transcript] != symbol:
                raise ValueError(f'Conflicting transcript mapping: {transcript!r}')
            tx[transcript] = symbol
            aliases[stable(transcript)].add(symbol)
            genes[symbol].add(stable(gid))
    for key, symbols in aliases.items():
        if len(symbols) == 1:
            tx.setdefault(key, next(iter(symbols)))
    return tx, genes


def initialize(tx):
    global TRANSCRIPTS
    TRANSCRIPTS = tx


def count_file(task):
    kind, sample, filename = task
    path = Path(filename)
    before = path.stat()
    expected, keycol = KINDS[kind][1:]
    counts = Counter()
    mapping_cache = {}
    rows = 0
    with path.open('rb', buffering=4*1024*1024) as handle:
        for line_no, line in enumerate(handle, 1):
            if not line.strip() or line.startswith((b'#', b'track ', b'browser ')):
                continue
            f = line.rstrip(b'\r\n').split(b'\t')
            if len(f) != expected:
                raise ValueError(f'{path}:{line_no}: expected {expected} columns, found {len(f)}')
            key = f[keycol]
            if kind in ('EXON', 'INTRON'):
                symbol = mapping_cache.get(key)
                if symbol is None:
                    transcript = key.rstrip(b';')
                    symbol = TRANSCRIPTS.get(transcript)
                    if symbol is None:
                        symbol = TRANSCRIPTS.get(stable(transcript))
                    if symbol is None:
                        raise ValueError(f'{path}:{line_no}: unmapped transcript {key!r}')
                    mapping_cache[key] = symbol
            else:
                symbol = key
            if not symbol or symbol == b'.':
                raise ValueError(f'{path}:{line_no}: missing gene symbol')
            counts[symbol] += 1
            rows += 1
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise RuntimeError(f'Input changed while being read: {path}')
    assert sum(counts.values()) == rows
    return sample, counts, {'region': kind, 'sample_id': sample, 'source_bed': str(path),
        'bytes': before.st_size, 'mtime_ns': before.st_mtime_ns, 'annotation_rows': rows,
        'nonzero_gene_symbols': len(counts), 'matrix_row_sum': sum(counts.values())}


def write_tsv(path, header, rows):
    tmp = path.with_suffix(path.suffix + '.tmp')
    with tmp.open('w', newline='') as handle:
        writer = csv.writer(handle, delimiter='\t', lineterminator='\n')
        writer.writerow(header)
        writer.writerows(rows)
    os.replace(tmp, path)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, default=Path('/inputs/ssb_upstream/ssb_run'))
    p.add_argument('--mapping', type=Path, default=Path('/inputs/reference/GRCh38.p14.R48_20250509/GRCh38.p14.v48.tranType.txt'))
    p.add_argument('--outdir', type=Path, required=True)
    p.add_argument('--regions', nargs='+', choices=KINDS, default=['GENE','EXON','TSS','INTRON'])
    p.add_argument('--append', action='store_true', help='Add new regions to a completed output directory without replacing matrices')
    p.add_argument('--workers', type=int, default=8)
    args = p.parse_args()
    if not 1 <= args.workers <= 30:
        p.error('--workers must be within 1..30')
    args.regions = list(dict.fromkeys(args.regions))
    args.outdir.mkdir(parents=True, exist_ok=True)
    tx, symbol_genes = load_mapping(args.mapping)
    print(f'Mapping loaded: {len(tx)} exact/stable transcript keys', flush=True)
    summaries, all_audit, sample_sets = [], [], {}
    previous_runs = []
    if args.append:
        prior = json.loads((args.outdir/'run_metadata.json').read_text())
        if prior['root'] != str(args.root) or prior['mapping_sha256'] != hashlib.sha256(args.mapping.read_bytes()).hexdigest():
            raise ValueError('Append requires identical source root and reference mapping')
        previous_runs = prior.get('previous_runs', []) + [{k:v for k,v in prior.items() if k != 'previous_runs'}]
        with (args.outdir/'matrix_summary.tsv').open() as h:
            summaries = list(csv.DictReader(h, delimiter='\t'))
        with (args.outdir/'sample_file_audit.tsv').open() as h:
            all_audit = list(csv.DictReader(h, delimiter='\t'))
        for row in all_audit:
            sample_sets.setdefault(row['region'], []).append(row['sample_id'])
    start = time.time()
    for region in args.regions:
        output = args.outdir / f'SSB_{region}_sample_by_gene_raw_counts.tsv'
        if output.exists():
            raise FileExistsError(f'Refusing to overwrite existing output: {output}')
        files = sorted((args.root / KINDS[region][0]).glob('*.bed'), key=lambda x: natural_key(x.name))
        if not files:
            raise FileNotFoundError(f'No BED files for {region}')
        samples = [f.name.removesuffix('.anno.bed') if f.name.endswith('.anno.bed') else f.stem for f in files]
        if len(samples) != len(set(samples)):
            raise ValueError(f'Duplicate sample IDs for {region}')
        sample_sets[region] = samples
        tasks = [(region, s, str(f)) for s,f in zip(samples, files)]
        result, audit = {}, {}
        with ProcessPoolExecutor(max_workers=args.workers, initializer=initialize, initargs=(tx,)) as pool:
            futures = [pool.submit(count_file, task) for task in tasks]
            for i, future in enumerate(as_completed(futures), 1):
                s, counts, info = future.result()
                result[s], audit[s] = counts, info
                if i % 20 == 0 or i == len(tasks):
                    print(f'{region}: {i}/{len(tasks)} samples; elapsed {time.time()-start:.0f}s', flush=True)
        symbols = sorted(set().union(*(c.keys() for c in result.values())))
        write_tsv(output, ['sample_id'] + [s.decode() for s in symbols],
            ([sample] + [result[sample].get(g, 0) for g in symbols] for sample in samples))
        # Independent read-back validation of dimensions, integer values and totals.
        with output.open(newline='') as handle:
            reader = csv.reader(handle, delimiter='\t')
            header = next(reader)
            assert len(header) == len(set(header)) == len(symbols)+1
            observed_samples = []
            for row in reader:
                assert len(row) == len(header)
                values = list(map(int, row[1:]))
                assert all(v >= 0 for v in values)
                assert sum(values) == audit[row[0]]['annotation_rows']
                observed_samples.append(row[0])
            assert observed_samples == samples
        all_audit.extend(audit[s] for s in samples)
        write_tsv(args.outdir/f'{region}_gene_symbol_dictionary.tsv', ['gene_symbol','gene_ids','number_of_gene_ids'],
            ([s.decode(),';'.join(g.decode() for g in sorted(symbol_genes.get(s, []))),len(symbol_genes.get(s, []))] for s in symbols))
        summaries.append({'region':region,'samples':len(samples),'gene_columns':len(symbols),
            'annotation_rows':sum(a['annotation_rows'] for a in audit.values()),'file':str(output),
            'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'validation':'PASS'})
        print(f'FINISHED {region}: {len(samples)} x {len(symbols)}; {output}', flush=True)
    write_tsv(args.outdir/'sample_file_audit.tsv', list(all_audit[0]), ([row[k] for k in all_audit[0]] for row in all_audit))
    write_tsv(args.outdir/'matrix_summary.tsv', list(summaries[0]), ([row[k] for k in summaries[0]] for row in summaries))
    regions = list(sample_sets)
    write_tsv(args.outdir/'sample_directory_presence.tsv', ['sample_id']+regions,
        ([s]+[int(s in sample_sets[r]) for r in regions] for s in sorted(set().union(*map(set,sample_sets.values())),key=natural_key)))
    (args.outdir/'run_metadata.json').write_text(json.dumps({'root':str(args.root),'mapping':str(args.mapping),
        'mapping_sha256':hashlib.sha256(args.mapping.read_bytes()).hexdigest(),'python':platform.python_version(),
        'workers':args.workers,'regions':regions,'regions_processed_this_run':args.regions,
        'elapsed_seconds':time.time()-start,'previous_runs':previous_runs},indent=2))
    (args.outdir/'README.txt').write_text('Each TSV has one sample per row, one gene symbol per column, and sample_id as the first column.\n'
        'Values count original annotation BED rows. Missing sample-gene combinations are 0.\n'
        'All BED samples are included, without QC303/clinical filtering or normalization.\n'
        'GENE: gene name column 8; TSS: gene name column 10; EXON/INTRON: transcript column 4 mapped with matching GENCODE v48 tranType.\n'
        'Transcript/overlap annotation multiplicity is preserved; values are NOT counts of unique genomic breaks.\n'
        'Different gene IDs with an identical symbol are aggregated; see gene_symbol_dictionary files.\n'
        'Samples are naturally sorted; genes are alphabetically sorted. Each region has its own observed gene set.\n'
        'Every matrix was read back; row sums equal counted BED annotation rows; malformed rows/unmapped transcripts cause failure.\n')


if __name__ == '__main__':
    main()
