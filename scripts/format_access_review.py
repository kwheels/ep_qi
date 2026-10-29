#!/usr/bin/env python3
"""Make a compact, editable review CSV from access_comparison.csv (Python 3.6+)."""
import argparse
import csv
import json
from pathlib import Path

TECHNIQUES = [("us", "Ultrasound"), ("venogram", "Venogram"),
              ("micro_puncture", "Micropuncture"), ("fluoroscopy", "Fluoroscopy")]
FIELDS = ["mrn", "procedure_date", "technique", "issue", "notes_value",
          "miheart_value", "manual_value", "notes_rows", "miheart_rows", "manual_rows",
          "resolved_value", "reviewer_comments"]


def source_values(records, technique):
    if not records:
        return "No record"
    values = {record["values"].get(technique) for record in records}
    labels = {0: "Not used (0)", 1: "Used (1)", None: "Unknown"}
    ordered = [v for v in (0, 1, None) if v in values]
    text = " | ".join(labels[v] for v in ordered)
    return "CONFLICT: " + text if 0 in values and 1 in values else text


def row_refs(records):
    return "; ".join("{} row {}".format(r["source_file"], r["source_row"]) for r in records)


def review_rows(rows):
    for row in rows:
        if row["in_both"] != "1":
            continue
        sources = {s: json.loads(row[s + "_records"]) for s in ("notes", "miheart", "manual")}
        for technique, label in TECHNIQUES:
            issues = []
            if row.get(technique + "_notes_conflict") == "1":
                issues.append("Conflicting note rows")
            if row.get(technique + "_database_conflict") == "1":
                issues.append("Conflicting database rows")
            if technique != "fluoroscopy":
                if row.get(technique + "_discrepancy") == "1" and not issues:
                    issues.append("Notes and database disagree")
                if not row.get(technique + "_notes") or not row.get(technique + "_database"):
                    if not issues:
                        issues.append("Incomplete comparison")
            if not issues:
                continue
            result = dict(mrn=row["mrn"], procedure_date=row["procedure_date"], technique=label,
                          issue="; ".join(issues), resolved_value="", reviewer_comments="")
            for source in sources:
                result[source + "_value"] = ("Not compared" if technique == "fluoroscopy" and source != "notes"
                                             else source_values(sources[source], technique))
                result[source + "_rows"] = row_refs(sources[source])
            yield result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.input.resolve() == args.output.resolve():
        parser.error("Input and output must differ.")
    # Comparison cells may contain full original notes serialized as JSON.
    import sys
    limit = sys.maxsize
    while True:
        try:
            csv.field_size_limit(limit)
            break
        except OverflowError:
            limit //= 10
    with args.input.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle, strict=True)
        required = {"mrn", "procedure_date", "in_both", "notes_records", "miheart_records", "manual_records"}
        if not required.issubset(reader.fieldnames or []):
            parser.error("Input must be access_comparison.csv from reconcile_access.py.")
        rows = list(review_rows(reader))
    with args.output.open("x", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    procedures = {(r["mrn"], r["procedure_date"]) for r in rows}
    print("Wrote {} technique-review rows for {} procedures.".format(len(rows), len(procedures)))


if __name__ == "__main__":
    main()
