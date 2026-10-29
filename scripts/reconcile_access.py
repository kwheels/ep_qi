#!/usr/bin/env python3
"""Clean reviewed access labels and optionally compare two Excel databases.

Python 3.6+; Excel reading requires openpyxl. No network operations.
"""
import argparse
import csv
import datetime as dt
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

TECHNIQUES = ("us", "venogram", "micro_puncture", "fluoroscopy")
COMPARE = TECHNIQUES[:3]
NOTE_COLUMNS = dict(mrn="phi_mrn", procedure_date="proc_date", us="ultrasound_used",
                    venogram="venogram_used", micro_puncture="micropuncture_used",
                    fluoroscopy="fluoroscopy_used")
DB_COLUMNS = dict(mrn="MRN", procedure_date="Procedure Date", us="US",
                  venogram="Venogram", micro_puncture="MicroPuncture")


def header_key(value):
    return re.sub(r"[^a-z0-9]", "", str(value).lower())


def column_map(headers, wanted):
    lookup = {}
    for name in headers:
        key = header_key(name)
        if key in lookup:
            raise ValueError("Duplicate/ambiguous header: " + str(name))
        lookup[key] = name
    missing = [v for v in wanted.values() if header_key(v) not in lookup]
    if missing:
        raise ValueError("Missing columns: " + ", ".join(missing))
    return {k: lookup[header_key(v)] for k, v in wanted.items()}


def mrn_text(value):
    text = str(value).strip() if value is not None else ""
    if re.fullmatch(r"\d+\.0+", text):
        text = text.split(".")[0]
    if not re.fullmatch(r"\d+", text):
        raise ValueError("MRN must contain digits only (no scientific notation).")
    return text


def date_text(value):
    if isinstance(value, dt.datetime):
        return value.date().isoformat()
    if isinstance(value, dt.date):
        return value.isoformat()
    text = str(value).strip()
    # US month/day/year, or ISO date with optional timestamp. No fuzzy dates.
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%Y/%m/%d"):
        try:
            return dt.datetime.strptime(text, fmt).date().isoformat()
        except ValueError:
            pass
    if re.match(r"^\d{4}-\d{2}-\d{2}[ T]", text):
        return dt.datetime.strptime(text[:10], "%Y-%m-%d").date().isoformat()
    raise ValueError("Unrecognized procedure date; use YYYY-MM-DD or MM/DD/YYYY.")


def binary(value, blank_zero=False):
    text = "" if value is None else str(value).strip().lower()
    if not text:
        return 0 if blank_zero else None
    if text in ("1", "1.0", "true", "t", "yes", "y"):
        return 1
    if text in ("0", "0.0", "false", "f", "no", "n"):
        return 0
    raise ValueError("Unrecognized technique value; expected blank, 0/1, or TRUE/FALSE.")


def csv_rows(path):
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle, strict=True)
        for number, row in enumerate(reader, 2):
            if None in row or any(v is None for v in row.values()):
                raise ValueError("Malformed CSV at record " + str(number))
            yield number, row, reader.fieldnames


def excel_rows(path, sheet=None):
    try:
        import openpyxl
    except ImportError:
        raise RuntimeError("Excel comparison requires: python3 -m pip install --user openpyxl")
    book = openpyxl.load_workbook(path, read_only=True, data_only=True)
    try:
        tab = book[sheet] if sheet else book.worksheets[0]
        iterator = tab.iter_rows(values_only=True)
        headers = next(iterator)
        # Ignore empty trailing Excel columns; populated unlabeled cells are errors.
        active = [i for i, h in enumerate(headers) if h is not None]
        for number, values in enumerate(iterator, 2):
            if not any(v is not None for v in values):
                continue
            if any(v is not None and i not in active for i, v in enumerate(values)):
                raise ValueError("Populated cell beneath an empty Excel header.")
            row = {str(headers[i]): values[i] if i < len(values) else None for i in active}
            yield number, row, list(row)
    finally:
        book.close()


def load_records(path, source, sheet=None, rejected=None):
    notes = source == "notes"
    iterator = csv_rows(path) if notes else excel_rows(path, sheet)
    records, mapping, counts = [], None, Counter()
    for number, original, headers in iterator:
        if mapping is None:
            mapping = column_map(headers, NOTE_COLUMNS if notes else DB_COLUMNS)
        try:
            mrn = mrn_text(original[mapping["mrn"]])
            date = date_text(original[mapping["procedure_date"]])
        except ValueError as exc:
            if rejected is None:
                raise ValueError("{} record {}: {} Use --quarantine-invalid to preserve invalid-key rows in a review file."
                                 .format(path.name, number, exc))
            rejected.append(dict(source=source, source_file=path.name, source_row=number,
                                 reason=str(exc), original_fields=dumps(original)))
            continue
        try:
            values = {t: binary(original[mapping[t]], blank_zero=notes)
                      for t in TECHNIQUES if t in mapping}
            if notes:
                for t in TECHNIQUES:
                    if original[mapping[t]] is None or str(original[mapping[t]]).strip() == "":
                        counts[t + "_blank_to_zero"] += 1
        except ValueError as exc:
            # Identify source row without printing PHI in console errors.
            raise ValueError("{} record {}: {}".format(path.name, number, exc))
        records.append(dict(source=source, source_file=path.name, source_row=number,
                            original=original, mrn=mrn, procedure_date=date, values=values,
                            key=(mrn.lstrip("0") or "0", date)))
    if not records:
        raise ValueError("No records in " + path.name)
    return records, counts


def consensus(records, technique):
    values = {r["values"].get(technique) for r in records}
    known = values - {None}
    conflict = len(known) > 1
    # A missing value in any duplicate source row prevents a complete consensus.
    value = next(iter(known)) if len(known) == 1 and None not in values else None
    return value, int(conflict), int(None in values)


def dumps(value):
    return json.dumps(value, default=str, ensure_ascii=False, sort_keys=True)


def write_csv(path, fields, rows, overwrite=False):
    with path.open("w" if overwrite else "x", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def reconcile(notes, database):
    groups = defaultdict(lambda: defaultdict(list))
    for record in notes + database:
        groups[record["key"]][record["source"]].append(record)
    clean, merged, audit = [], [], []
    for key in sorted(groups):
        sources = groups[key]
        nr = sources.get("notes", [])
        db = sources.get("miheart", []) + sources.get("manual", [])
        all_records = nr + db
        # Preserve the reviewed MRN text if present; match via separate canonical key.
        mrn = (nr or db)[0]["mrn"]
        result = dict(mrn=mrn, procedure_date=key[1], mrn_match_key=key[0],
                      in_notes=int(bool(nr)), in_miheart=int(bool(sources.get("miheart"))),
                      in_manual=int(bool(sources.get("manual"))), in_database=int(bool(db)),
                      in_both=int(bool(nr and db)))
        clean_row = dict(mrn=mrn, procedure_date=key[1])
        any_conflict, incomplete, disagreements = False, False, []
        for source in ("notes", "miheart", "manual"):
            rows = sources.get(source, [])
            result[source + "_row_count"] = len(rows)
            result[source + "_records"] = dumps([
                dict(source_file=r["source_file"], source_row=r["source_row"],
                     mrn=r["mrn"], procedure_date=r["procedure_date"],
                     values=r["values"], original=r["original"]) for r in rows])
        for technique in TECHNIQUES:
            nv, nc, nm = consensus(nr, technique)
            clean_row[technique] = nv
            result[technique + "_notes"] = nv
            result[technique + "_notes_conflict"] = nc
            result[technique + "_notes_values"] = dumps([r["values"].get(technique) for r in nr])
            any_conflict |= bool(nc)
            if technique in COMPARE:
                dv, dc, dm = consensus(db, technique)
                result[technique + "_database"] = dv
                result[technique + "_database_conflict"] = dc
                result[technique + "_database_values"] = dumps([r["values"].get(technique) for r in db])
                for source in ("miheart", "manual"):
                    result[technique + "_" + source] = consensus(sources.get(source, []), technique)[0]
                # Known conflicting source values always require adjudication.
                disagree = 1 if nc or dc else int(nv != dv) if nv is not None and dv is not None else None
                result[technique + "_discrepancy"] = disagree if nr and db else None
                if nr and db:
                    disagreements.append(disagree)
                    incomplete |= nv is None or dv is None
                any_conflict |= bool(dc)
                combined = {r["values"].get(technique) for r in all_records}
            else:
                combined = {r["values"].get(technique) for r in nr}
            # Combined fields stay blank on disagreement or unknown input values.
            result[technique] = next(iter(combined)) if len(combined) == 1 else None
        result["any_discrepancy"] = (1 if 1 in disagreements else
                                     0 if disagreements and all(v == 0 for v in disagreements) else None)
        result["duplicate_conflict"] = int(any_conflict)
        result["comparison_incomplete"] = int(bool(nr and db and incomplete))
        result["needs_review"] = int(any_conflict or result["any_discrepancy"] == 1 or
                                     result["comparison_incomplete"] or not result["in_both"])
        if nr:
            clean.append(clean_row)
        merged.append(result)
        for record in all_records:
            audit.append(dict(mrn_match_key=key[0], procedure_date=key[1], source=record["source"],
                              source_file=record["source_file"], source_row=record["source_row"],
                              original_fields=dumps(record["original"])))
    return clean, merged, audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--folder", type=Path, default=Path("/home/kwheels/cied_complications"))
    parser.add_argument("--notes", type=Path)
    parser.add_argument("--miheart", type=Path)
    parser.add_argument("--manual", type=Path)
    parser.add_argument("--miheart-sheet")
    parser.add_argument("--manual-sheet")
    parser.add_argument("--clean-only", action="store_true")
    parser.add_argument("--quarantine-invalid", action="store_true",
                        help="Save rows with invalid MRN/date in rejected_rows.csv; compare valid keys only.")
    parser.add_argument("--out-dir", type=Path, required=True, help="New directory; must not exist.")
    args = parser.parse_args()
    if args.out_dir.exists():
        parser.error("Output directory already exists; choose a new name.")
    rejected = [] if args.quarantine_invalid else None
    notes, counts = load_records(args.notes or args.folder / "access_technique_reviewed.csv", "notes", rejected=rejected)
    database = []
    if not args.clean_only:
        for source, path, sheet in [
            ("miheart", args.miheart or args.folder / "Micropuncture.xlsx", args.miheart_sheet),
            ("manual", args.manual or args.folder / "manual_procedure_review.xlsx", args.manual_sheet)]:
            records, _ = load_records(path, source, sheet, rejected=rejected)
            database.extend(records)
    clean, merged, audit = reconcile(notes, database)
    args.out_dir.mkdir(parents=True, exist_ok=False)
    write_csv(args.out_dir / "access_technique_clean.csv", ["mrn", "procedure_date"] + list(TECHNIQUES), clean)
    write_csv(args.out_dir / "source_records.csv", list(audit[0]), audit)
    if args.quarantine_invalid:
        write_csv(args.out_dir / "rejected_rows.csv",
                  ["source", "source_file", "source_row", "reason", "original_fields"], rejected)
    if not args.clean_only:
        write_csv(args.out_dir / "access_comparison.csv", list(merged[0]), merged)
        write_csv(args.out_dir / "access_comparison_review.csv", list(merged[0]),
                  [r for r in merged if r["needs_review"]])
    summary = dict(note_rows=len(notes), database_rows=len(database),
                   invalid_key_rows=len(rejected or []), input_review_required=int(bool(rejected)),
                   invalid_key_rows_by_source=dict(Counter(r["source"] for r in rejected or [])),
                   note_procedures=len(clean), union_procedures=len(merged),
                   blank_to_zero=dict(counts),
                   duplicate_conflict_procedures=sum(r["duplicate_conflict"] for r in merged))
    if not args.clean_only:
        summary.update(in_both=sum(r["in_both"] for r in merged),
                       discrepant=sum(r["any_discrepancy"] == 1 for r in merged),
                       incomplete=sum(r["comparison_incomplete"] for r in merged),
                       review=sum(r["needs_review"] for r in merged))
    with (args.out_dir / "summary.json").open("x", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2)
    print(dumps(summary))
    if rejected:
        print("WARNING: Invalid-key rows were excluded from matching and preserved in rejected_rows.csv. "
              "Comparison is provisional until these rows are reviewed and corrected.")


if __name__ == "__main__":
    main()
