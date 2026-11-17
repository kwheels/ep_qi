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
            ("Subcutaneous coil insertion", "Subcutaneous coil insertion", "tunneled_nontransvenous_component"),
            ("Lead insertion", "Lead insertion: Medtronic lead Sub-Q Lead 6996SQ", "tunneled_nontransvenous_component"),
            ("Lead insertion", "Lead insertion: Medtronic lead 6996S", "tunneled_nontransvenous_component"),
            ("Lead revision", "Lead revision", "lead_revision_reposition_review"),
            ("Lead repair", "Lead repair", "lead_repair_only"),
            ("Atrial device insertion", "Atrial device insertion: Abbott IPG LSP201A", "leadless_pacemaker"),
            ("Right ventricular device insertion", "Right ventricular device insertion: Abbott IPG LSP202V", "leadless_pacemaker"),
            ("ICD insertion", "ICD insertion: Boston Scientific Sub-Q ICD", "subcutaneous_icd"),
            ("ICD insertion", "ICD insertion: Medtronic Extravascular ICD", "extravascular_icd"),
            ("EV-ICD insertion", "EV-ICD insertion", "extravascular_icd"),
            ("Lead insertion", "Lead insertion: Medtronic lead EV240163", "extravascular_icd"),
            ("ICD insertion", "ICD insertion: Medtronic Aurora", "extravascular_icd"),
            ("ICD insertion", "ICD insertion: Medtronic ICD DVEA3E4 Aurora EV-ICD MRI", "extravascular_icd"),
            ("New Implantation of an EV-CD", "New Implantation of an EV-CD", "extravascular_icd"),
            ("S-ICD insertion", "S-ICD insertion", "subcutaneous_icd"),
            ("ICD insertion", "ICD insertion: Boston Scientific transvenous ICD with a subcutaneous pocket", "transvenous_icd_implant"),
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
                "10": "- US-guided femoral venous access\n- Dual chamber leadless pacemaker implant (Aveir DR)\n- Please apply pressure to your groin. Do not apply lotions",
                "11": "- Dual chamber leadless pacemaker implant (Aveir DR)\n- Right ventricular lead insertion",
                "12": "- Dual chamber leadless pacemaker implant (Aveir DR)\n- Lead reposition",
                "13": "- Lead reposition\n- Device interrogation and programming",
                "16": "- Lead repair\n- Device interrogation and programming\n- No driving for 24 hours",
                "17": "- Lead repair\n- Right ventricular lead insertion",
                "18": "- Lead insertion: Medtronic lead Sub-Q Lead 6996SQ\n- Insertion of TYRX envelope\n- Defibrillation threshold test\n- Device interrogation and programming",
                "19": "- Subcutaneous coil insertion\n- Right ventricular lead insertion: Synthetic transvenous lead",
                "15": "- ICD insertion: Medtronic ICD DVEA3E4 Aurora EV-ICD MRI\n- Lead insertion: Medtronic lead EV240163\n- Insertion of TYRX Absorbable antibacterial envelope\n- Defibrillation threshold test\n- Device interrogation and programming",
            }
            with source.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.writer(handle)
                writer.writerow(["phi_mrn", "proc_date", "full_note"])
                for mrn, items in cases.items():
                    writer.writerow([mrn, "2024-01-01", "PROCEDURES PERFORMED:\n" + items + "\nANESTHESIA: General"])
                writer.writerow(["8", "2024-01-01", "No requested section"])
                writer.writerow(["14", "2024-01-01", "PROCEDURE: Dual chamber leadless pacemaker implant\nPROCEDURES PERFORMED:\n- Atrial device insertion: Synthetic manufacturer\n- Right ventricular device insertion: Synthetic manufacturer\nANESTHESIA: MAC"])
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
            self.assertEqual(rows["10"]["note_access_eligible"], "0")
            self.assertEqual(rows["10"]["eligibility_status"], "excluded_leadless_only")
            self.assertEqual(rows["10"]["needs_review"], "0")
            self.assertEqual(rows["11"]["note_access_eligible"], "1")
            self.assertEqual(rows["12"]["note_access_eligible"], "")
            self.assertEqual(rows["12"]["needs_review"], "1")
            self.assertEqual(rows["13"]["eligibility_status"], "revision_requires_positive_access_flag")
            self.assertEqual(rows["13"]["needs_review"], "0")
            self.assertEqual(rows["14"]["eligibility_status"], "excluded_leadless_only")
            self.assertEqual(rows["15"]["note_access_eligible"], "0")
            self.assertEqual(rows["15"]["has_extravascular_icd"], "1")
            self.assertEqual(rows["15"]["needs_review"], "0")
            self.assertEqual(rows["16"]["note_access_eligible"], "0")
            self.assertEqual(rows["16"]["eligibility_status"], "excluded_lead_repair_only")
            self.assertEqual(rows["16"]["needs_review"], "0")
            self.assertEqual(rows["17"]["note_access_eligible"], "1")
            self.assertEqual(rows["18"]["note_access_eligible"], "0")
            self.assertEqual(rows["18"]["has_tunneled_access"], "1")
            self.assertEqual(rows["18"]["tunneled_access_only"], "1")
            self.assertEqual(rows["18"]["needs_review"], "0")
            self.assertEqual(rows["19"]["note_access_eligible"], "1")
            self.assertEqual(rows["19"]["has_tunneled_access"], "1")
            self.assertEqual(rows["19"]["tunneled_access_only"], "0")
            self.assertEqual(rows["7"]["generator_miheart_check"], "1")
            self.assertEqual(rows["8"]["eligibility_status"], "excluded_missing_procedures_section")
            marker = output / "my_notes.md"
            marker.write_text("keep me")
            categorize_inventory(inventory, output)
            self.assertEqual(marker.read_text(), "keep me")
            with (output / "procedure_eligibility.csv").open(newline="", encoding="utf-8") as handle:
                self.assertEqual(len(list(csv.DictReader(handle))), 19)

    def test_subq_extravascular_and_mixed_case(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as temp:
            root = Path(temp)
            source = root / "notes.csv"
            with source.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.writer(handle)
                writer.writerow(["phi_mrn", "proc_date", "full_note"])
                for mrn, items, history in [
                    ("1", "- ICD insertion: Boston Scientific Sub-Q ICD", ""),
                    ("2", "- ICD insertion: Medtronic Extravascular ICD", ""),
                    ("3", "- Sub-Q ICD removal\n- Atrial lead insertion\n- Pacemaker insertion", ""),
                    ("4", "- ICD insertion: Transvenous ICD", "HISTORY: Previous Sub-Q ICD removal.\n")]:
                    writer.writerow([mrn, "2024-01-01", history + "PROCEDURES PERFORMED:\n" + items + "\nANESTHESIA: General"])
                writer.writerow(["5", "2024-01-01",
                    "PROCEDURES PERFORMED:\n- Ultrasound guidance for venous access\nANESTHESIA: MAC\n"
                    "PROCEDURES PERFORMED:\n- Upper extremity venogram for venous access\n"
                    "Incision Care Instructions\n- No driving for 24 hours post implant\n"
                    "- Right ventricular lead insertion: Synthetic lead\n- Lead abandon: Old lead\nANESTHESIA: MAC"])
            build_inventory(source, root / "inventory")
            categorize_inventory(root / "inventory", root / "categories")
            with (root / "categories/procedure_eligibility.csv").open(newline="", encoding="utf-8") as handle:
                rows = {r["mrn"]: r for r in csv.DictReader(handle)}
            self.assertEqual(rows["1"]["note_access_eligible"], "0")
            self.assertEqual(rows["2"]["note_access_eligible"], "0")
            self.assertEqual(rows["3"]["note_access_eligible"], "1")
            self.assertEqual(rows["3"]["nontransvenous_device_needs_review"], "1")
            self.assertEqual(rows["4"]["note_access_eligible"], "1")
            self.assertEqual(rows["4"]["note_mentions_subcutaneous_icd"], "1")
            self.assertEqual(rows["4"]["nontransvenous_device_needs_review"], "1")
            self.assertEqual(rows["5"]["note_access_eligible"], "1")
            self.assertEqual(rows["5"]["eligibility_status"], "qualifying_implant_documented")
            self.assertIn("Section extraction needs review", rows["5"]["review_reasons"])


if __name__ == "__main__":
    unittest.main()
