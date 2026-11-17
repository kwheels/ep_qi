#!/usr/bin/env python3
"""Export selected cases from a saved final analysis CSV. Python 3.6+, no packages."""
import argparse
import csv
import re
import sys
from pathlib import Path


def export_cases(source, output_dir, groups):
    limit = sys.maxsize
    while True:
        try:
            csv.field_size_limit(limit)
            break
        except OverflowError:
            limit //= 10
    with source.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        fields = reader.fieldnames or []
        if "database_rows" not in fields:
            raise ValueError("Input must contain database_rows (use final_procedure_dataset.csv).")
        records = list(reader)
    fields = [f for f in ("mrn", "procedure_date") if f in fields] + [f for f in fields if f not in {"mrn", "procedure_date"}]
    outputs = [output_dir / name for name in groups] + [output_dir / "qc_case_export_status.csv"]
    if any(path.resolve() == source.resolve() for path in outputs):
        raise ValueError("Output must not overwrite input.")
    output_dir.mkdir(parents=True, exist_ok=True)
    status = []
    for name, references in groups.items():
        requested = set(references)
        matched, counts = [], dict.fromkeys(references, 0)
        for row in records:
            hits = requested & set(re.split(r"\s*;\s*", row["database_rows"].strip()))
            if hits:
                matched.append(dict(row, matched_database_row_references="; ".join(sorted(hits))))
                for hit in hits:
                    counts[hit] += 1
        with (output_dir / name).open("w", newline="", encoding="utf-8-sig") as handle:
            writer = csv.DictWriter(handle, fieldnames=["matched_database_row_references"] + fields)
            writer.writeheader()
            writer.writerows(matched)
        for reference, count in counts.items():
            status.append(dict(output_file=name, database_row_reference=reference, final_dataset_matches=count,
                               status="Present in final analysis dataset" if count else "Not found in this final dataset; check eligibility audit"))
        print("{}: {} matching procedure row(s)".format(name, len(matched)))
    with (output_dir / "qc_case_export_status.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=["output_file", "database_row_reference", "final_dataset_matches", "status"])
        writer.writeheader()
        writer.writerows(status)
    print("Exports saved in {}".format(output_dir))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path, default=Path("/home/kwheels/cied_complications/hrs_abstract_output/private/final_procedure_dataset.csv"))
    parser.add_argument("--out-dir", type=Path, help="Defaults to the input file's existing directory.")
    parser.add_argument("--eligibility-rows", nargs="+", default=["659", "1884", "747", "1146"])
    parser.add_argument("--ptx-rows", nargs="+", default=["2630", "2007"])
    args = parser.parse_args()
    export_cases(args.input, args.out_dir or args.input.parent, {
        "qc_eligibility_cases.csv": args.eligibility_rows,
        "qc_ptx_no_access_cases.csv": args.ptx_rows})


if __name__ == "__main__":
    main()
