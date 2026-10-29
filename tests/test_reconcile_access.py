import csv
import datetime as dt
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from reconcile_access import binary, column_map, date_text, mrn_text, reconcile, load_records, DB_COLUMNS


def record(source, mrn="00123", date="2024-07-19", values=None, row=2):
    values = values or dict(us=1, venogram=0, micro_puncture=1, fluoroscopy=0)
    return dict(source=source, source_file=source + ".csv", source_row=row,
                mrn=mrn, procedure_date=date, key=(mrn.lstrip("0"), date), values=values,
                original=dict(MRN=mrn, procedure_date=date, **values))


class ReconciliationTests(unittest.TestCase):
    def test_invalid_keys_preserved_for_review(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as temp:
            path = Path(temp) / "notes.csv"
            with path.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.writer(handle)
                writer.writerow(["phi_mrn", "proc_date", "ultrasound_used", "venogram_used",
                                 "micropuncture_used", "fluoroscopy_used"])
                writer.writerow(["00123", "2024-07-19", 1, 0, 1, 0])
                writer.writerow(["", "2024-07-19", 0, 1, 0, 0])
                writer.writerow(["MRN_UNKNOWN", "2024-07-19", 1, 1, 1, 0])
                writer.writerow(["00456", "not a date", 1, 0, 1, 0])
            with self.assertRaisesRegex(ValueError, "record 3"):
                load_records(path, "notes")
            rejected = []
            records, counts = load_records(path, "notes", rejected=rejected)
            self.assertEqual(len(records), 1)
            self.assertEqual(len(rejected), 3)
            self.assertEqual(rejected[0]["source_row"], 3)
            self.assertEqual(json.loads(rejected[1]["original_fields"])["phi_mrn"], "MRN_UNKNOWN")
            self.assertEqual(json.loads(rejected[2]["original_fields"])["proc_date"], "not a date")

    def test_normalization(self):
        self.assertEqual(binary("" , True), 0)
        self.assertIsNone(binary(None))
        self.assertEqual(binary(True), 1)
        self.assertEqual(binary("FALSE"), 0)
        self.assertEqual(mrn_text("00123"), "00123")
        self.assertEqual(mrn_text(123.0), "123")
        self.assertEqual(date_text("7/19/2024"), "2024-07-19")
        self.assertEqual(date_text(dt.datetime(2024, 7, 19)), "2024-07-19")
        self.assertEqual(date_text("2024-07-19 10:20:00"), "2024-07-19")
        with self.assertRaises(ValueError):
            binary("uncertain")
        with self.assertRaises(ValueError):
            mrn_text("1.23e2")
        with self.assertRaises(ValueError):
            date_text("not a date")
        mapping = column_map(["mrn", "procedure_date", "us", "Venogram", "MicroPuncture"], DB_COLUMNS)
        self.assertEqual(mapping["micro_puncture"], "MicroPuncture")

    def test_match_leading_zeros_and_dates(self):
        clean, merged, audit = reconcile([record("notes")], [record("miheart", mrn="123")])
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["in_both"], 1)
        self.assertEqual(merged[0]["any_discrepancy"], 0)
        self.assertEqual(clean[0]["mrn"], "00123")
        self.assertEqual(len(audit), 2)

    def test_discrepancy_preserves_both(self):
        db = record("manual", values=dict(us=0, venogram=0, micro_puncture=1))
        row = reconcile([record("notes")], [db])[1][0]
        self.assertEqual(row["any_discrepancy"], 1)
        self.assertEqual((row["us_notes"], row["us_database"], row["us"]), (1, 0, None))
        self.assertEqual(json.loads(row["manual_records"])[0]["original"]["us"], 0)

    def test_duplicate_conflict_no_cartesian_join(self):
        notes = [record("notes"), record("notes", row=3)]
        db = [record("miheart"), record("manual", values=dict(us=0, venogram=0, micro_puncture=1))]
        clean, merged, _ = reconcile(notes, db)
        self.assertEqual((len(clean), len(merged)), (1, 1))
        row = merged[0]
        self.assertEqual(row["duplicate_conflict"], 1)
        self.assertIsNone(row["us_database"])
        self.assertIsNone(row["us"])
        self.assertEqual((row["us_miheart"], row["us_manual"]), (1, 0))
        self.assertEqual(row["any_discrepancy"], 1)

    def test_note_conflict_clean_field_blank(self):
        a = record("notes")
        b = record("notes", values=dict(us=0, venogram=0, micro_puncture=1, fluoroscopy=0), row=3)
        clean, merged, audit = reconcile([a, b], [])
        self.assertIsNone(clean[0]["us"])
        self.assertEqual(merged[0]["duplicate_conflict"], 1)
        self.assertEqual(len(audit), 2)

    def test_unmatched_and_missing_are_not_agreement(self):
        notes = [record("notes")]
        db = [record("miheart", mrn="456")]
        rows = reconcile(notes, db)[1]
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(r["in_both"] == 0 and r["any_discrepancy"] is None for r in rows))
        db = [record("miheart", values=dict(us=None, venogram=0, micro_puncture=1))]
        row = reconcile(notes, db)[1][0]
        self.assertEqual(row["comparison_incomplete"], 1)
        self.assertIsNone(row["any_discrepancy"])
        self.assertIsNone(row["us"])

    def test_end_to_end_excel_and_csv(self):
        try:
            import openpyxl
        except ImportError:
            self.skipTest("openpyxl unavailable")
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as temp:
            folder = Path(temp)
            with (folder / "access_technique_reviewed.csv").open("w", newline="", encoding="utf-8-sig") as handle:
                writer = csv.writer(handle)
                writer.writerow(["phi_mrn", "proc_date", "ultrasound_used", "venogram_used",
                                 "micropuncture_used", "fluor\noscopy_used"])
                writer.writerow(["00123", "07/19/2024", "1", "", "1", "0"])
            for filename, mrn in [("Micropuncture.xlsx", 123), ("manual_procedure_review.xlsx", 456)]:
                book = openpyxl.Workbook()
                sheet = book.active
                sheet.append(["MRN", "procedure_date", "us", "Venogram", "MicroPuncture"])
                sheet.append([mrn, dt.datetime(2024, 7, 19), True, False, True])
                book.save(folder / filename)
                book.close()
            output = folder / "output"
            subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / "scripts" / "reconcile_access.py"),
                            "--folder", str(folder), "--out-dir", str(output)], check=True, capture_output=True)
            with (output / "access_comparison.csv").open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]["any_discrepancy"], "0")
            self.assertEqual(rows[0]["mrn"], "00123")
            self.assertEqual(rows[1]["in_both"], "0")
            self.assertEqual(rows[1]["any_discrepancy"], "")
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(summary["blank_to_zero"]["venogram_blank_to_zero"], 1)


if __name__ == "__main__":
    unittest.main()
