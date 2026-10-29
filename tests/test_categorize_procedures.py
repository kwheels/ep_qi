import csv
import tempfile
import unittest
from pathlib import Path
from scripts.categorize_procedures import categorize, run as categorize_inventory
from index_procedures import run as build_inventory


class ProcedureCategoryTests(unittest.TestCase):
    def test_categories_and_raw_device_context(self):
        cases = [
            ("Pacemaker insertion", "Pacemaker insertion: Dual chamber transvenous device", "transvenous_pacemaker_implant"),
            ("ICD insertion", "ICD insertion: Vendor", "transvenous_icd_implant"),
            ("Implantation of new RV ICD lead", "Implantation of new RV ICD lead", "transvenous_lead_insertion"),
            ("Unsuccessful CS lead implant", "Unsuccessful CS lead implant", "attempted_transvenous_lead_implant"),
            ("Inability to deploy a satisfactory CS lead", "Inability to deploy a satisfactory CS lead", "attempted_transvenous_lead_implant"),
            ("Pacemaker insertion (RA)", "Pacemaker insertion (RA): Aveir leadless device", "leadless_pacemaker"),
            ("Temporary venous pacemaker placement", "Temporary venous pacemaker placement", "temporary_pacing"),
            ("ILR removal", "ILR removal", "ilr_insertion_removal"),
            ("ICD generator insertion", "ICD generator insertion", "generator_only_or_change_miheart_check"),
            ("EP study", "EP study", "ep_study_or_stimulation"),
            ("Lead extraction", "Lead extraction", "device_or_lead_removal_only"),
            ("Subcutaneous coil insertion", "Subcutaneous coil insertion", "nontransvenous_system_review"),
            ("Lead revision", "Lead revision", "lead_revision_reposition_review"),
        ]
        for label, raw, expected in cases:
            with self.subTest(label=label):
                self.assertEqual(categorize(label, raw), expected)

    def test_case_level_mixed_procedures(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as temp:
            folder = Path(temp)
            source = folder / "notes.csv"
            cases = {
                "1": "- ILR removal\n- Pacemaker insertion",
                "2": "- ILR insertion",
                "3": "- EP study\n- Temporary venous pacemaker placement",
                "4": "- Failed LV lead implantation in the CS",
                "5": "- Pacemaker insertion (RA): Aveir leadless device",
                "6": "- Temporary venous pacemaker placement\n- ICD insertion",
                "7": "- Generator change",
            }
            with source.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.writer(handle)
                writer.writerow(["phi_mrn", "proc_date", "full_note"])
                for mrn, items in cases.items():
                    writer.writerow([mrn, "2024-01-01", "PROCEDURES PERFORMED:\n" + items + "\nANESTHESIA: General"])
                writer.writerow(["8", "2024-01-01", "No requested section"])
                writer.writerow(["9", "2024-01-01", "PROCEDURES PERFORMED:\n- ILR removal\nANESTHESIA: Local\nPROCEDURES PERFORMED:\n- ICD insertion\nANESTHESIA: General"])
            inventory, output = folder / "inventory", folder / "categorized"
            build_inventory(source, inventory)
            categorize_inventory(inventory, output)
            with (output / "procedure_eligibility.csv").open(newline="", encoding="utf-8") as handle:
                rows = {r["mrn"]: r for r in csv.DictReader(handle)}
            for mrn in ["1", "4", "6", "9"]:
                self.assertEqual(rows[mrn]["note_access_eligible"], "1")
            for mrn in ["2", "3", "5", "7", "8"]:
                self.assertEqual(rows[mrn]["note_access_eligible"], "0")
            self.assertEqual(rows["7"]["generator_miheart_check"], "1")
            self.assertEqual(rows["8"]["eligibility_status"], "excluded_missing_procedures_section")
            marker = output / "my_notes.md"
            marker.write_text("keep me")
            categorize_inventory(inventory, output)
            self.assertEqual(marker.read_text(), "keep me")
            with (output / "procedure_eligibility.csv").open(newline="", encoding="utf-8") as handle:
                self.assertEqual(len(list(csv.DictReader(handle))), 9)


if __name__ == "__main__":
    unittest.main()
