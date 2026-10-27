import csv
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from parse_micropuncture import classify


class ExtractionTests(unittest.TestCase):
    def test_documentation_labels(self):
        cases = [
            ("Using a Seldinger technique and fluoroscopic guidance, a\nmicropuncture needle was inserted into the axillary vein which was\nexchanged for a J-tip 0.035 wire.", "documented_use"),
            ("Access obtained using a micro-puncture needle.", "documented_use"),
            ("No micropuncture needle was used.", "explicit_non_use"),
            ("Micropuncture was not used.", "explicit_non_use"),
            ("We did not use a micropuncture needle.", "explicit_non_use"),
            ("A micropuncture kit was available.", "uncertain_mention"),
            ("Micropuncture access was attempted but unsuccessful.", "uncertain_mention"),
            ("Prior micropuncture access was used.", "uncertain_mention"),
            ("Micropuncture needle.", "uncertain_mention"),
            ("No micropuncture was used. Later a micropuncture needle was inserted.", "mixed_mentions"),
            ("A standard needle was used.", "not_mentioned"),
            ("", "missing_note"),
        ]
        for note, expected in cases:
            with self.subTest(note=note):
                self.assertEqual(classify(note)[0], expected)

    def test_multiline_csv_and_identifier_preservation(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.csv"
            target = Path(directory) / "output.csv"
            with source.open("w", newline="", encoding="utf-8-sig") as handle:
                writer = csv.DictWriter(handle, fieldnames=["phi_mrn", "note_id", "full_note"])
                writer.writeheader()
                writer.writerow(dict(phi_mrn="00012345", note_id="a",
                                     full_note='PROCEDURE:\nA micropuncture needle was inserted, using "guidance".'))
                writer.writerow(dict(phi_mrn="00012345", note_id="b", full_note="No access description."))
            subprocess.run([sys.executable, str(Path(__file__).with_name("parse_micropuncture.py")),
                            str(source), str(target)], check=True, capture_output=True)
            with target.open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]["phi_mrn"], "00012345")
            self.assertEqual(rows[0]["micropuncture_used"], "1")
            self.assertEqual(rows[1]["micropuncture_used"], "")
            self.assertNotIn("micropuncture_evidence", rows[0])


if __name__ == "__main__":
    unittest.main()
