import csv
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from parse_micropuncture import classify, access_course

# Synthetic regression case mirroring failed attempts followed by cutdown.
ACCESS_COURSE_NOTE = (
    "Ultrasound-guided access was performed at the axillary vein. "
    "The J wire would not advance into the subclavian vein. "
    "We performed contrast venography showing axillary vein spasm. "
    "We attempted venous access of the subclavian vein using contrast venography "
    "and fluoroscopy, but tortuosity meant we were unable to advance the J wire. "
    "We then proceeded to perform a cephalic vein cutdown. "
    "Cephalic vein cutdown was performed. "
    "Venous access was successfully achieved using a micropuncture needle, "
    "confirming via fluoroscopy the presence of the wires in the vena cava."
)


class ExtractionTests(unittest.TestCase):
    def test_failed_access_and_cutdown(self):
        difficulty, conversion = access_course(ACCESS_COURSE_NOTE)
        self.assertTrue(difficulty)
        self.assertTrue(conversion)
        self.assertIn("would not advance", " ".join(difficulty))
        self.assertIn("cephalic vein cutdown", " ".join(conversion))
        for technique in ["ultrasound", "micropuncture", "cephalic_cutdown"]:
            self.assertEqual(classify(ACCESS_COURSE_NOTE, technique)[:3],
                             ("documented_use", "1", 1))
        self.assertEqual(classify(ACCESS_COURSE_NOTE, "venogram")[:3],
                         ("mixed_mentions", "", 1))
        self.assertEqual(classify(ACCESS_COURSE_NOTE, "fluoroscopy")[:3],
                         ("mixed_mentions", "", 1))
        self.assertEqual(access_course("Lead positioning was difficult. No complications."), ([], []))
        self.assertEqual(classify("Cephalic vein cutdown was considered.", "cephalic_cutdown")[0],
                         "uncertain_mention")
        self.assertEqual(classify("No cephalic vein cutdown was performed.", "cephalic_cutdown")[0],
                         "explicit_non_use")

    def test_ultrasound_aliases_and_review(self):
        for term in ["USG", "USG-guided", "US guidance", "US guided", "US guidence", "U/S",
                     "ultrsound", "ultrasoud", "ultrasond", "ultrasounnd", "ultrsaound"]:
            with self.subTest(term=term):
                status, used, review, evidence, count = classify(
                    "Venous access was obtained using " + term + ".", "ultrasound")
                self.assertEqual((status, used, review, count), ("documented_use", "1", 1, 1))
                self.assertIn(term, evidence[0])
        self.assertEqual(classify("Venous access obtained without USG.", "ultrasound")[:3],
                         ("explicit_non_use", "0", 1))
        self.assertEqual(classify("USG was considered for venous access.", "ultrasound")[:3],
                         ("uncertain_mention", "", 1))
        self.assertEqual(classify("USG showed no effusion.", "ultrasound")[0],
                         "mention_without_access_context")
        self.assertEqual(classify("The patient asked us about venous access.", "ultrasound")[0],
                         "not_mentioned")
        self.assertEqual(classify("Discuss access in the US guidelines.", "ultrasound")[0],
                         "not_mentioned")
        self.assertEqual(classify("Venous access obtained using ultrasound.", "ultrasound")[2], 0)

    def test_access_guidance(self):
        cases = [
            ("Ultrasound-guided axillary vein access was obtained.", "ultrasound", "documented_use"),
            ("US-guided venous access was obtained.", "ultrasound", "documented_use"),
            ("Using fluoroscopic guidance, a micropuncture needle was inserted into the axillary vein.", "fluoroscopy", "documented_use"),
            ("Upper extremity venogram for venous access", "venogram", "documented_use"),
            ("Upper extremity venogram was performed for venous access.", "venogram", "documented_use"),
            ("Venography was performed to guide axillary vein puncture.", "venogram", "documented_use"),
            ("Lead slack was assessed with fluoroscopy.", "fluoroscopy", "mention_without_access_context"),
            ("FLUORO TIME: 11.1 min", "fluoroscopy", "mention_without_access_context"),
            ("Ultrasound showed no pericardial effusion.", "ultrasound", "mention_without_access_context"),
            ("Venous access was obtained without ultrasound.", "ultrasound", "explicit_non_use"),
            ("Ultrasound was considered for venous access.", "ultrasound", "uncertain_mention"),
            ("Venous access obtained under fluoroscopic guidance. Lead slack checked with fluoroscopy.", "fluoroscopy", "documented_use"),
            ("Venous access obtained using ultrasound and fluoroscopy.", "ultrasound", "documented_use"),
            ("Venous access obtained using ultrasound and fluoroscopy.", "fluoroscopy", "documented_use"),
        ]
        for note, technique, expected in cases:
            with self.subTest(note=note, technique=technique):
                self.assertEqual(classify(note, technique)[0], expected)

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
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as directory:
            source = Path(directory) / "input.csv"
            target = Path(directory) / "output.csv"
            with source.open("w", newline="", encoding="utf-8-sig") as handle:
                writer = csv.DictWriter(handle, fieldnames=["phi_mrn", "note_id", "full_note"])
                writer.writeheader()
                writer.writerow(dict(phi_mrn="00012345", note_id="a",
                                     full_note='PROCEDURE:\nA micropuncture needle was inserted, using "guidance".'))
                writer.writerow(dict(phi_mrn="00012345", note_id="b", full_note="No access description."))
                writer.writerow(dict(phi_mrn="00012345", note_id="c",
                                     full_note="Venous access obtained with USG guidance."))
                writer.writerow(dict(phi_mrn="00012345", note_id="d", full_note=ACCESS_COURSE_NOTE))
            subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / "scripts" / "parse_micropuncture.py"),
                            str(source), str(target), "--include-evidence"], check=True, capture_output=True)
            with target.open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 4)
            self.assertEqual(rows[0]["phi_mrn"], "00012345")
            self.assertEqual(rows[0]["micropuncture_used"], "1")
            self.assertEqual(rows[1]["micropuncture_used"], "")
            self.assertIn("micropuncture needle", rows[0]["micropuncture_evidence"])
            self.assertEqual(rows[2]["ultrasound_used"], "1")
            self.assertEqual(rows[2]["ultrasound_needs_review"], "1")
            self.assertEqual(rows[2]["ultrasound_variant_match"], "1")
            self.assertEqual(rows[2]["ultrasound_matched_terms"], "USG")
            self.assertEqual(rows[3]["access_course_needs_review"], "1")
            self.assertEqual(rows[3]["access_difficulty_or_attempt"], "1")
            self.assertEqual(rows[3]["access_conversion"], "1")
            self.assertEqual(rows[3]["cephalic_cutdown_used"], "1")
            self.assertIn("would not advance", rows[3]["access_difficulty_evidence"])
            self.assertIn("cephalic vein cutdown", rows[3]["access_conversion_evidence"])


if __name__ == "__main__":
    unittest.main()
