import csv
import datetime as dt
import tempfile
import unittest
from pathlib import Path

from demographic_extraction.extract_demographics import extract, mrn_value


class DemographicExtractionTests(unittest.TestCase):
    def test_mrn_preservation_and_numeric_qc(self):
        self.assertEqual(mrn_value("001234567"), ("001234567", ""))
        self.assertEqual(mrn_value(1234567), ("1234567", "numeric_mrn_verify_leading_zeros"))
        self.assertEqual(mrn_value(1234567, 9), ("001234567", ""))
        self.assertEqual(mrn_value("NULL"), ("", "missing_mrn"))

    def test_workbook_join_history_long_and_conflicts(self):
        import openpyxl
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as temp:
            folder = Path(temp)
            book = openpyxl.Workbook()
            master = book.active
            master.title = "PatientInfo"
            master.append(["PatientID", "MRN", "DOB"])
            master.append(["GUID-A", "00123", dt.datetime(1950, 1, 2)])
            master.append(["GUID-B", "00456", dt.datetime(1960, 3, 4)])
            master.append(["GUID-C", "00789", None])
            master.append(["GUID-C", "00999", None])
            master.append(["GUID-D", "00123", None])
            demo = book.create_sheet("DemographicInfo")
            demo.append(["PatientID", "Sex"])
            demo.append(["guid-a", "Female"])
            demo.append(["GUID-B", "Male"])
            demo.append(["UNKNOWN", "Other"])
            history = book.create_sheet("ClarityMedicalHistory")
            history.append(["PatientID", "ProblemDescription"])
            history.append(["GUID-A", "Hypertension"])
            history.append(["GUID-A", "Hypertension"])
            history.append(["GUID-A", "Diabetes"])
            history.append(["GUID-B", None])
            history.append(["UNKNOWN", "Other problem"])
            meds = book.create_sheet("MedicationAdministrations")
            meds.append(["PatientID", "Medication", "Time"])
            meds.append(["GUID-A", "Drug A", dt.datetime(2024, 1, 1, 12, 30)])
            meds.append(["GUID-A", "Drug B", dt.datetime(2024, 1, 1, 13, 30)])
            meds.append(["UNKNOWN", "Drug C", None])
            meds.append([None, "Drug D", None])
            wb = folder / "source.xlsx"
            book.save(wb)
            book.close()
            output = folder / "output"
            report = extract(wb, output)

            def read(name):
                with (output / name).open(newline="", encoding="utf-8") as handle:
                    return list(csv.DictReader(handle))

            rows = read("patients.csv")
            self.assertEqual(len(rows), 4)
            self.assertEqual(list(rows[0])[:2], ["MRN", "PatientID"])
            a = next(r for r in rows if r["PatientID"] == "GUID-A")
            self.assertEqual(a["MRN"], "00123")
            self.assertEqual(a["PatientInfo__DOB"], "1950-01-02")
            self.assertEqual(a["DemographicInfo__Sex"], "Female")
            self.assertEqual(a["ClarityMedicalHistory__ProblemDescription"], "Hypertension | Diabetes")
            self.assertEqual(next(r for r in rows if r["PatientID"] == "GUID-C")["MRN"], "")
            long = read("long/MedicationAdministrations.csv")
            self.assertEqual(len(long), 4)
            self.assertEqual(long[0]["MRN"], "00123")
            self.assertEqual(long[0]["Time"], "2024-01-01 12:30:00")
            self.assertEqual(long[2]["MRN"], "")
            self.assertEqual(report["sheet_classifications"]["DemographicInfo"], "patient_level")
            self.assertEqual(report["sheet_classifications"]["MedicationAdministrations"], "repeated_measures")
            issues = read("qc_issues.csv")
            self.assertTrue(any(r["issue"] == "conflicting_patientid_mrn_mapping" for r in issues))
            self.assertTrue(any(r["issue"] == "mrn_shared_by_multiple_patientids" for r in issues))
            self.assertEqual(len(read("unmatched_rows.csv")), 4)
            marker = output / "my_review.txt"
            marker.write_text("retain")
            extract(wb, output)
            self.assertEqual(marker.read_text(), "retain")
            self.assertEqual(len(read("patients.csv")), 4)


if __name__ == "__main__":
    unittest.main()
