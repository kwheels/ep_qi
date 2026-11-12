"""End-to-end synthetic abstract script check; set RSCRIPT to a local Rscript."""
import csv
import datetime as dt
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class AbstractRunnerTests(unittest.TestCase):
    def test_complete_analysis_and_value_free_schemas(self):
        rscript = os.environ.get("RSCRIPT") or shutil.which("Rscript")
        if not rscript:
            self.skipTest("Rscript unavailable; set RSCRIPT to run the integration test")
        import openpyxl
        repo = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as directory:
            root = Path(directory)
            demo = root / "demographic_extraction_output"
            demo.mkdir()
            (demo / "long").mkdir()
            (root / "procedure_categories_v1").mkdir()

            def csv_file(path, headers, rows):
                with path.open("w", newline="", encoding="utf-8") as handle:
                    writer = csv.writer(handle)
                    writer.writerow(headers)
                    writer.writerows(rows)

            def workbook(name, identifiers):
                book = openpyxl.Workbook()
                sheet = book.active
                sheet.append(["MRN", "PatientKey", "Pouch", "ProcedureDate", "ProcedureList", "us", "Venogram", "MicroPuncture"])
                for i in identifiers:
                    sheet.append([str(i).zfill(5), "synthetic-guid-" + str(i), "Unknown", dt.datetime(2024, 1, 1),
                                  "Lead Reposition" if i == 9 else "New Implant", i % 2 == 0, i % 3 == 0, i % 2 == 1])
                book.save(root / name)
                book.close()

            workbook("Micropuncture.xlsx", range(1, 11))
            workbook("manual_procedure_review.xlsx", [1, 11])
            csv_file(root / "access_technique_reviewed.csv", ["phi_mrn", "proc_date", "ultrasound_used", "venogram_used", "micropuncture_used", "fluoroscopy_used"],
                     [[str(i).zfill(5), "2024-01-01", int(i % 2 == 0), int(i % 3 == 0), 1, int(i % 3 != 0)] for i in range(1, 7)])
            csv_file(root / "procedure_categories_v1/procedure_eligibility.csv", ["mrn", "procedure_date", "note_access_eligible"],
                     [[str(i), "2024-01-01", 0 if i == 6 else 1] for i in range(1, 7)])
            csv_file(root / "ptx_patients_clean.csv", ["mrn", "date_diagnosed"], [["1", "01/02/2024"], ["3", "01/03/2024"]])
            csv_file(demo / "patients.csv", ["MRN", "PatientID", "PatientInfo__DOB", "DemographicInfo__Sex", "DemographicInfo__Ethnicity", "ClarityMedicalHistory__ProblemDescription"],
                     [[str(i).zfill(5), "synthetic-guid-" + str(i), "06/01/1950 00:00", "Female" if i % 2 else "Male", "Example ethnicity",
                       "SYNTHETIC_PRIVATE_DIAGNOSIS | Condition B"] for i in range(1, 12)])
            output = root / "hrs_abstract_output"
            # Paths are R string literals, passed as a structured process argument.
            import json
            expression = ('options(hrs.data_dir=' + json.dumps(root.as_posix()) + '); '
                          'source("analysis/hrs_abstract_analysis.R")')
            environment = os.environ.copy()
            if os.environ.get("R_TEST_LIBRARY"):
                environment["R_LIBS_USER"] = os.environ["R_TEST_LIBRARY"]
            result = subprocess.run([rscript, "--vanilla", "-e", expression], cwd=str(repo), env=environment,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            with (output / "shareable/cohort_counts.csv").open(newline="", encoding="utf-8") as handle:
                counts = next(csv.DictReader(handle))
            self.assertEqual(counts["included_procedures"], "10")
            self.assertEqual(counts["included_patients_with_valid_mrn"], "10")
            self.assertEqual(counts["included_without_note"], "5")
            with (output / "shareable/demographics_summary.csv").open(newline="", encoding="utf-8") as handle:
                demographics = next(csv.DictReader(handle))
            self.assertEqual(demographics["n_age_known"], "10")
            self.assertEqual(demographics["mean_age"], "73")
            with (output / "shareable/access_chisquared.csv").open(newline="", encoding="utf-8") as handle:
                comparisons = list(csv.DictReader(handle))
            self.assertEqual(len(comparisons), 3)
            for path in (output / "shareable").glob("*"):
                self.assertNotIn("SYNTHETIC_PRIVATE_DIAGNOSIS", path.read_text(encoding="utf-8"))
                self.assertNotIn("synthetic-guid-", path.read_text(encoding="utf-8"))
            self.assertTrue((output / "private/diagnosis_terms_for_review.csv").exists())


if __name__ == "__main__":
    unittest.main()
