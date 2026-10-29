import csv
import tempfile
import unittest
from pathlib import Path
from index_procedures import extract, procedure_label, run


class ProcedureIndexTests(unittest.TestCase):
    def test_wrapped_items_and_boundaries(self):
        text = ("PROCEDURE: Ignore this\nPROCEDURES PERFORMED:\n"
                "- Pacemaker insertion: Vendor Model\n serial detail\n"
                "- Atrial lead insertion: Device\n- Upper extremity venogram for venous access\n"
                "ANESTHESIA: General\nHISTORY: Loop recorder insertion")
        items, block, issues = extract(text)
        self.assertEqual(len(items), 3)
        self.assertEqual(issues, [])
        self.assertEqual(procedure_label(items[0]), "Pacemaker insertion")
        self.assertNotIn("HISTORY", block)

    def test_missing_unbulleted_inline_and_multiple(self):
        self.assertEqual(extract("No heading")[2], ["missing_procedures_section"])
        self.assertEqual(extract("PROCEDURES PERFORMED: - implant")[2], ["missing_anesthesia_boundary"])
        self.assertEqual(len(extract("PROCEDURES PERFORMED: - Implant - Lead insertion ANESTHESIA: Local")[0]), 2)
        self.assertIn("unbulleted_section_review_splitting", extract("PROCEDURES PERFORMED: Loop recorder insertion ANESTHESIA: Local")[2])
        self.assertIn("multiple_procedures_sections", extract("PROCEDURES PERFORMED: - Implant ANESTHESIA: Local PROCEDURES PERFORMED: - Other ANESTHESIA: Local")[2])

    def test_all_duplicate_sections_and_no_discharge_spill(self):
        text = ("PROCEDURES PERFORMED:\n- ILR removal\nANESTHESIA: Local\n"
                "RECOMMENDATION:\n- Wash your incision with soap\n"
                "PROCEDURES PERFORMED:\n- Pacemaker insertion\nANESTHESIA: General")
        items, _, flags = extract(text)
        self.assertEqual(items, ["ILR removal", "Pacemaker insertion"])
        self.assertIn("multiple_procedures_sections", flags)
        text = "PROCEDURES PERFORMED:\n- ICD insertion\nRECOMMENDATION:\n- Wash your incision"
        items, _, flags = extract(text)
        self.assertEqual(items, ["ICD insertion"])
        self.assertIn("alternative_section_boundary", flags)

    def test_frequency_counts_distinct_procedures_and_patients(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as directory:
            folder = Path(directory)
            path = folder / "input.csv"
            with path.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.writer(handle)
                writer.writerow(["phi_mrn", "proc_date", "full_note"])
                for date in ["2024-01-01", "2024-01-01", "2024-02-01"]:
                    writer.writerow(["00123", date, "PROCEDURES PERFORMED:\n- Loop recorder insertion: Vendor\nANESTHESIA: Local"])
            output = folder / "output"
            run(path, output)
            with (output / "procedure_index.csv").open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["procedure_count"], "2")
            self.assertEqual(rows[0]["patient_count"], "1")
            self.assertEqual(rows[0]["source_note_count"], "3")
            self.assertEqual(rows[0]["loop_recorder_term"], "1")


if __name__ == "__main__":
    unittest.main()
