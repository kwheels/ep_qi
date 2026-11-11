#!/usr/bin/env python3
"""Extract patient-level and repeated-measure CSVs from a multi-tab workbook.

Python 3.6+ and openpyxl. No network access; source workbook is read-only.
"""
import argparse
import csv
import datetime as dt
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


def normalized(value):
    return re.sub(r"[^a-z0-9]", "", str(value).lower())


def patient_key(value):
    return "" if value is None else str(value).strip().casefold()


def cell_text(value):
    if value is None:
        return ""
    if isinstance(value, dt.datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, dt.date):
        return value.isoformat()
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    return str(value).strip()


def field_text(header, value):
    if normalized(header) in ("dob", "dateofbirth", "birthdate") and isinstance(value, dt.datetime):
        return value.date().isoformat()
    return cell_text(value)


def find_column(headers, name, required=True):
    found = [h for h in headers if normalized(h) == normalized(name)]
    if len(found) > 1 or (not found and required):
        raise ValueError("Missing or ambiguous column: " + name)
    return found[0] if found else None


def sheet_headers(sheet):
    values = next(sheet.iter_rows(min_row=1, max_row=1, values_only=True), ())
    headers = [cell_text(v) for v in values]
    nonempty = [normalized(h) for h in headers if h]
    if len(nonempty) != len(set(nonempty)):
        raise ValueError("Duplicate/ambiguous headers in " + sheet.title)
    return headers


def sheet_rows(sheet, headers):
    for number, values in enumerate(sheet.iter_rows(min_row=2, values_only=True), 2):
        if not any(cell_text(v) for v in values):
            continue
        if any(cell_text(v) and (i >= len(headers) or not headers[i]) for i, v in enumerate(values)):
            raise ValueError("Data beneath empty header: {} row {}".format(sheet.title, number))
        yield number, {h: values[i] if i < len(values) else None for i, h in enumerate(headers) if h}


def mrn_value(value, width=None):
    text = cell_text(value)
    if not text or text.casefold() in ("null", "na", "n/a", "none"):
        return "", "missing_mrn"
    numeric = isinstance(value, (int, float)) and not isinstance(value, bool)
    if numeric and isinstance(value, float) and value.is_integer():
        text = str(int(value))
    if not re.fullmatch(r"[0-9]+", text):
        return "", "invalid_mrn"
    if width:
        if len(text) > width:
            return "", "mrn_exceeds_requested_width"
        text = text.zfill(width)
    return text, "numeric_mrn_verify_leading_zeros" if numeric and not width else ""


def csv_writer(path, fields):
    handle = path.open("w", newline="", encoding="utf-8")
    writer = csv.DictWriter(handle, fieldnames=fields)
    writer.writeheader()
    return handle, writer


def extract(workbook_path, output, mrn_width=None):
    import openpyxl
    workbook_path, output = Path(workbook_path), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    long_dir = output / "long"
    long_dir.mkdir(exist_ok=True)
    book = openpyxl.load_workbook(workbook_path, read_only=True, data_only=True)
    handles = []
    try:
        sheet_lookup = {normalized(name): name for name in book.sheetnames}
        if len(sheet_lookup) != len(book.sheetnames):
            raise ValueError("Ambiguous worksheet names after normalization.")
        if "patientinfo" not in sheet_lookup:
            raise ValueError("Required PatientInfo tab missing.")
        master = book[sheet_lookup["patientinfo"]]
        headers = sheet_headers(master)
        id_col, mrn_col = find_column(headers, "PatientID"), find_column(headers, "MRN")
        master_fields = ["MRN", "PatientID"] + ["PatientInfo__" + h for h in headers if h and h not in (id_col, mrn_col)]
        patients, master_rows, qc_counts = {}, defaultdict(list), Counter()
        master_total_rows = 0
        audit_fields = ["issue", "sheet", "source_row", "PatientID", "MRN", "details", "original_fields"]
        qh, qc = csv_writer(output / "qc_issues.csv", audit_fields)
        uh, unmatched = csv_writer(output / "unmatched_rows.csv", audit_fields)
        handles.extend([qh, uh])

        def issue(kind, sheet, rownum, row, pid="", mrn="", details="", unmatched_row=False):
            qc_counts[kind] += 1
            result = dict(issue=kind, sheet=sheet, source_row=rownum, PatientID=pid, MRN=mrn,
                          details=details, original_fields=json.dumps(row, default=cell_text, ensure_ascii=False))
            qc.writerow(result)
            if unmatched_row:
                unmatched.writerow(result)

        for number, row in sheet_rows(master, headers):
            master_total_rows += 1
            key = patient_key(row[id_col])
            if not key:
                issue("missing_patient_id", master.title, number, row, unmatched_row=True)
                continue
            mrn, warning = mrn_value(row[mrn_col], mrn_width)
            if warning:
                issue(warning, master.title, number, row, cell_text(row[id_col]), mrn)
            master_rows[key].append((number, row, mrn))
        if not master_rows:
            raise ValueError("No usable PatientIDs in PatientInfo.")
        for key, rows in master_rows.items():
            known_mrns = {mrn for _, _, mrn in rows if mrn}
            mrn = next(iter(known_mrns)) if len(known_mrns) == 1 else ""
            patient = dict(MRN=mrn, PatientID=cell_text(rows[0][1][id_col]))
            if len(rows) > 1:
                for number, original, original_mrn in rows:
                    issue("duplicate_patientinfo_id", master.title, number, original, patient["PatientID"], original_mrn)
            if len(known_mrns) > 1:
                for number, original, original_mrn in rows:
                    issue("conflicting_patientid_mrn_mapping", master.title, number, original,
                          patient["PatientID"], original_mrn, "Master MRN left blank; conflicting originals retained here.")
            for h in headers:
                if not h or h in (id_col, mrn_col):
                    continue
                values = list(dict.fromkeys(field_text(h, original[h]) for _, original, _ in rows if cell_text(original[h])))
                patient["PatientInfo__" + h] = values[0] if len(values) == 1 else ""
                if len(values) > 1:
                    for number, original, original_mrn in rows:
                        issue("conflicting_patientinfo_field", master.title, number, original,
                              patient["PatientID"], original_mrn, h + " left blank in master.")
            patients[key] = patient
        reverse = defaultdict(list)
        for key, patient in patients.items():
            if patient["MRN"]:
                reverse[patient["MRN"].lstrip("0") or "0"].append(key)
        for keys in reverse.values():
            if len(keys) > 1:
                for key in keys:
                    for number, original, mrn in master_rows[key]:
                        issue("mrn_shared_by_multiple_patientids", master.title, number, original,
                              patients[key]["PatientID"], mrn, "PatientIDs remain separate; review before MRN merge.")

        summary = [dict(sheet=master.title, classification="patient_mapping", row_count=master_total_rows,
                        unique_patient_ids=len(patients), repeated_patient_ids=sum(len(r) > 1 for r in master_rows.values()),
                        output_file="patients.csv")]
        used_files = set()
        for sheet in book.worksheets:
            if sheet.title == master.title:
                continue
            headers = sheet_headers(sheet)
            pid_col = find_column(headers, "PatientID", required=False)
            seen, repeated, row_count = set(), set(), 0
            for _, row in sheet_rows(sheet, headers):
                row_count += 1
                key = patient_key(row.get(pid_col)) if pid_col else ""
                if key:
                    if key in seen:
                        repeated.add(key)
                    seen.add(key)
            history = normalized(sheet.title) == "claritymedicalhistory"
            classification = "medical_history" if history else "unkeyed" if not pid_col else "repeated_measures" if repeated else "patient_level"
            if history and not pid_col:
                raise ValueError("ClarityMedicalHistory needs PatientID.")
            problem_col = find_column(headers, "ProblemDescription") if history else None
            output_file = "patients.csv"
            if classification in ("unkeyed", "repeated_measures"):
                filename = re.sub(r"[^A-Za-z0-9_.-]+", "_", sheet.title).strip("._") or "sheet"
                filename += ".csv"
                if filename.casefold() in used_files:
                    raise ValueError("Worksheet output filename collision: " + filename)
                used_files.add(filename.casefold())
                output_file = "long/" + filename
                others = [h for h in headers if h and h != pid_col]
                long_columns = {h: sheet.title + "__" + h if normalized(h) in ("mrn", "sourcerow") else h for h in others}
                if len(set(long_columns.values())) != len(long_columns):
                    raise ValueError("Repeated-measure output column collision in " + sheet.title)
                lh, long_writer = csv_writer(long_dir / filename, ["MRN", "PatientID", "source_row"] + list(long_columns.values()))
                handles.append(lh)
            else:
                new_fields = [sheet.title + "__" + problem_col] if history else [
                    sheet.title + "__" + h for h in headers if h and h != pid_col]
                if set(new_fields) & set(master_fields):
                    raise ValueError("Output column collision in " + sheet.title)
                master_fields.extend(new_fields)
            problems = defaultdict(dict)
            for number, row in sheet_rows(sheet, headers):
                key = patient_key(row.get(pid_col)) if pid_col else ""
                patient = patients.get(key)
                pid = cell_text(row.get(pid_col)) if pid_col else ""
                mrn = patient["MRN"] if patient else ""
                if not patient:
                    issue("unmatched_patient_id" if key else "missing_patient_id", sheet.title, number, row,
                          pid, "", unmatched_row=True)
                if classification in ("unkeyed", "repeated_measures"):
                    result = {long_columns[h]: field_text(h, row[h]) for h in others}
                    result.update(MRN=mrn, PatientID=pid, source_row=number)
                    long_writer.writerow(result)
                elif patient:
                    if history:
                        description = cell_text(row[problem_col])
                        if description:
                            problems[key][description] = None
                    else:
                        for h in headers:
                            if h and h != pid_col:
                                patient[sheet.title + "__" + h] = field_text(h, row[h])
            if history:
                for key, descriptions in problems.items():
                    patients[key][sheet.title + "__" + problem_col] = " | ".join(descriptions)
            summary.append(dict(sheet=sheet.title, classification=classification, row_count=row_count,
                                unique_patient_ids=len(seen), repeated_patient_ids=len(repeated), output_file=output_file))
        ph, pw = csv_writer(output / "patients.csv", master_fields)
        handles.append(ph)
        pw.writerows(patients.values())
        sh, sw = csv_writer(output / "sheet_summary.csv", list(summary[0]))
        handles.append(sh)
        sw.writerows(summary)
        report = dict(patient_rows=len(patients), patients_with_mrn=sum(bool(p["MRN"]) for p in patients.values()),
                      qc_issue_counts=dict(qc_counts), sheet_classifications={s["sheet"]: s["classification"] for s in summary})
        with (output / "summary.json").open("w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2)
        print(json.dumps(report))
        return report
    finally:
        for handle in handles:
            handle.close()
        book.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workbook", type=Path)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--mrn-width", type=int, help="Optional confirmed fixed width; default preserves text MRNs exactly.")
    args = parser.parse_args()
    if args.mrn_width is not None and args.mrn_width < 1:
        parser.error("--mrn-width must be positive")
    extract(args.workbook, args.out_dir, args.mrn_width)


if __name__ == "__main__":
    main()
