import csv
import tempfile
import unittest
from pathlib import Path
from scripts.export_analysis_cases import export_cases


class CaseExportTests(unittest.TestCase):
    def test_exact_references_preserve_identifiers_and_report_missing(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "final.csv"
            source.write_text("mrn,procedure_date,database_rows\n000123,2024-01-01,659; 747\n000456,2024-01-02,1659\n")
            export_cases(source, root, {"cases.csv": ["659", "747", "999"]})
            with (root / "cases.csv").open(encoding="utf-8-sig", newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["mrn"], "000123")
            self.assertEqual(rows[0]["matched_database_row_references"], "659; 747")
            with (root / "qc_case_export_status.csv").open(encoding="utf-8-sig", newline="") as handle:
                status = list(csv.DictReader(handle))
            self.assertEqual([r["final_dataset_matches"] for r in status], ["1", "1", "0"])
            self.assertIn("1659", source.read_text())


if __name__ == "__main__":
    unittest.main()
