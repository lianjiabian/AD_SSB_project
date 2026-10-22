#!/usr/bin/env python3
"""Independent final read-back validation for all four SSB count matrices."""
import argparse
import csv
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('outdir', type=Path)
args = p.parse_args()
with (args.outdir/'matrix_summary.tsv').open() as h:
    summary = list(csv.DictReader(h, delimiter='\t'))
assert {x['region'] for x in summary} == {'GENE','EXON','INTRON','TSS'}
with (args.outdir/'sample_file_audit.tsv').open() as h:
    audit = {(x['region'],x['sample_id']):int(x['annotation_rows']) for x in csv.DictReader(h, delimiter='\t')}
sample_lists = []
results = []
for x in summary:
    path = Path(x['file'])
    assert hashlib.sha256(path.read_bytes()).hexdigest() == x['sha256']
    with path.open(newline='') as h:
        reader = csv.reader(h, delimiter='\t')
        header = next(reader)
        assert header[0] == 'sample_id'
        assert len(header) == len(set(header)) == int(x['gene_columns'])+1
        ids, total = [], 0
        for row in reader:
            assert len(row) == len(header)
            vals = list(map(int,row[1:]))
            assert min(vals) >= 0
            count = sum(vals)
            assert count == audit[(x['region'],row[0])]
            ids.append(row[0])
            total += count
        assert len(ids) == len(set(ids)) == int(x['samples'])
        assert total == int(x['annotation_rows'])
        sample_lists.append(ids)
        results.append({'region':x['region'],'samples':len(ids),'genes':len(header)-1,'sum_counts':total,'status':'PASS'})
assert all(ids == sample_lists[0] for ids in sample_lists)
report = {'all_four_sample_orders_identical':True,'matrices':results,'status':'PASS'}
(args.outdir/'FINAL_VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
