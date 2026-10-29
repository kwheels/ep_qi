import unittest
from reconcile_access import reconcile
from test_reconcile_access import record
from format_access_review import review_rows


def csv_strings(row):
    return {k: "" if v is None else str(v) for k, v in row.items()}


class CompactReviewTests(unittest.TestCase):
    def test_only_different_technique_and_both_sources(self):
        notes = [record("notes")]
        database = [record("miheart", values=dict(us=0, venogram=0, micro_puncture=1)),
                    record("manual", mrn="456")]
        merged = reconcile(notes, database)[1]
        rows = list(review_rows(map(csv_strings, merged)))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["technique"], "Ultrasound")
        self.assertEqual(rows[0]["notes_value"], "Used (1)")
        self.assertEqual(rows[0]["miheart_value"], "Not used (0)")
        self.assertEqual(rows[0]["manual_value"], "No record")
        self.assertEqual(rows[0]["resolved_value"], "")
        self.assertIn("row 2", rows[0]["miheart_rows"])

    def test_conflicting_duplicates_and_unknown(self):
        database = [record("miheart", values=dict(us=1, venogram=None, micro_puncture=1)),
                    record("manual", values=dict(us=0, venogram=0, micro_puncture=1))]
        merged = reconcile([record("notes")], database)[1]
        rows = list(review_rows(map(csv_strings, merged)))
        self.assertEqual(len(rows), 2)
        self.assertIn("Conflicting database rows", rows[0]["issue"])
        self.assertEqual(rows[0]["miheart_value"], "Used (1)")
        self.assertEqual(rows[0]["manual_value"], "Not used (0)")
        self.assertEqual(rows[1]["miheart_value"], "Unknown")


if __name__ == "__main__":
    unittest.main()
