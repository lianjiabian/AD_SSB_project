import tempfile
import unittest
from pathlib import Path
import merge_ssb_bed_sample_by_gene as merge


class CountingTests(unittest.TestCase):
    def test_annotation_multiplicity_and_mapping(self):
        merge.initialize({b'ENST1.1': b'GENEA', b'ENST2.1': b'GENEA'})
        with tempfile.TemporaryDirectory(prefix='ssb_matrix_test_') as d:
            p = Path(d)/'S1.anno.bed'
            lines = []
            for tx in ('ENST1.1;', 'ENST1.1;', 'ENST2.1;'):
                lines.append('\t'.join(['chr1','0','10',tx,'+','chr1','1','2','read1','0','+']))
            p.write_text('\n'.join(lines)+'\n')
            _,counts,audit = merge.count_file(('EXON','S1',str(p)))
            self.assertEqual(counts, {b'GENEA':3})
            self.assertEqual(audit['annotation_rows'], 3)

    def test_direct_symbols_and_empty_file(self):
        with tempfile.TemporaryDirectory(prefix='ssb_matrix_test_') as d:
            p = Path(d)/'S2.anno.bed'
            for kind in ('GENE','TSS'):
                n,col = merge.KINDS[kind][1:]
                fields = ['x']*n
                fields[col] = 'GENEB'
                p.write_text('\t'.join(fields)+'\n')
                self.assertEqual(merge.count_file((kind,'S2',str(p)))[1],{b'GENEB':1})
            p.write_text('')
            self.assertEqual(merge.count_file(('GENE','S2',str(p)))[2]['annotation_rows'],0)

    def test_unmapped_and_malformed_fail(self):
        merge.initialize({})
        with tempfile.TemporaryDirectory(prefix='ssb_matrix_test_') as d:
            p = Path(d)/'S3.anno.bed'
            p.write_text('\t'.join(['x']*11)+'\n')
            with self.assertRaisesRegex(ValueError,'unmapped'):
                merge.count_file(('EXON','S3',str(p)))
            p.write_text('invalid\n')
            with self.assertRaisesRegex(ValueError,'columns'):
                merge.count_file(('GENE','S3',str(p)))

    def test_par_suffix_preserved(self):
        self.assertEqual(merge.stable(b'ENST1.5_PAR_Y;'),b'ENST1_PAR_Y')


if __name__ == '__main__':
    unittest.main()
