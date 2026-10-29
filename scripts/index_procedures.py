#!/usr/bin/env python3
"""Index procedures listed between PROCEDURES PERFORMED and ANESTHESIA.

Run alongside reconcile_access.py. Python 3.6+, standard library only.
"""
import argparse
import csv
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

from reconcile_access import date_text, mrn_text, write_csv

START = re.compile(r"\bPROCEDURES?\s+PERFORMED\s*:", re.I)
END = re.compile(r"\bAN(?:A)?ESTHESIA\s*:", re.I)
BULLET = re.compile(r"(?:^|\n)\s*(?:[-*\u2022]|\d+[.)])\s+|[ \t]+[-\u2022][ \t]+")
LOOP = re.compile(r"\b(?:loop\s+recorder|implantable\s+(?:cardiac|heart)\s+monitor|ILR|ICM)\b", re.I)


def extract(note):
    text = unicodedata.normalize("NFKC", note or "").replace("\r\n", "\n").replace("\r", "\n")
    starts = list(START.finditer(text))
    if not starts:
        return [], "", ["missing_procedures_section"]
    start = starts[0]
    end = END.search(text, start.end())
    if not end:
        return [], "", ["missing_anesthesia_boundary"]
    block = text[start.end():end.start()].strip()
    issues = ["multiple_procedures_sections"] if len(starts) > 1 else []
    if not block:
        return [], block, issues + ["empty_procedures_section"]
    if BULLET.search(block):
        items = [re.sub(r"\s+", " ", item).strip() for item in BULLET.split(block)]
        items = [item for item in items if item]
    else:
        # Do not guess which wrapped lines represent separate interventions.
        items = [re.sub(r"\s+", " ", block).strip()]
        issues.append("unbulleted_section_review_splitting")
    return items, block, issues


def procedure_label(item):
    # Device manufacturer/model/serial details commonly follow the first colon.
    # Retain complete original item in procedure_items.csv for review.
    label = item.split(":", 1)[0].strip()
    return re.sub(r"\s+", " ", label).rstrip(" .;") or item


def header_choice(headers, choices):
    matches = [c for c in choices if c in headers]
    if not matches:
        raise ValueError("Missing required column; expected one of " + ", ".join(choices))
    return matches[0]


def run(input_path, output_dir):
    if output_dir.exists():
        raise ValueError("Output directory already exists; choose a new name.")
    limit = sys.maxsize
    while True:
        try:
            csv.field_size_limit(limit)
            break
        except OverflowError:
            limit //= 10
    records, items_out, index = [], [], {}
    with input_path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle, strict=True)
        headers = reader.fieldnames or []
        if len(headers) != len(set(headers)):
            raise ValueError("Duplicate column names.")
        mrn_column = header_choice(headers, ["phi_mrn", "mrn_norm", "mrn"])
        date_column = header_choice(headers, ["proc_date", "procedure_date"])
        if "full_note" not in headers:
            raise ValueError("Input needs full_note; use the original reconstruction CSV, not the reviewed technique export.")
        for source_row, row in enumerate(reader, 2):
            if None in row or any(v is None for v in row.values()):
                raise ValueError("Malformed CSV at record " + str(source_row))
            issues = []
            try:
                mrn = mrn_text(row[mrn_column])
                date = date_text(row[date_column])
                key = (mrn.lstrip("0") or "0", date)
            except ValueError:
                mrn, date, key = row[mrn_column], row[date_column], None
                issues.append("invalid_mrn_or_date")
            items, section, extraction_issues = extract(row["full_note"])
            issues.extend(extraction_issues)
            labels = [procedure_label(item) for item in items]
            common = dict(source_row=source_row, mrn=mrn, procedure_date=date, note_id=row.get("note_id", ""))
            records.append(dict(common, procedure_count=len(items), distinct_procedure_count=len(set(l.casefold() for l in labels)),
                                procedures=" | ".join(labels), loop_recorder_mentioned=int(any(LOOP.search(i) for i in items)),
                                needs_review=int(bool(issues)), review_reason="; ".join(issues), procedures_section=section))
            for number, (item, label) in enumerate(zip(items, labels), 1):
                normalized = label.casefold()
                if normalized not in index:
                    index[normalized] = dict(label=label, mentions=0, rows=set(), procedures=set(), patients=set(),
                                             invalid_rows=set(), variants=set())
                entry = index[normalized]
                entry["mentions"] += 1
                entry["rows"].add(source_row)
                entry["variants"].add(label)
                if key is not None:
                    entry["procedures"].add(key)
                    entry["patients"].add(key[0])
                else:
                    entry["invalid_rows"].add(source_row)
                items_out.append(dict(common, item_number=number, procedure_label=label, original_item=item,
                                      needs_review=int(bool(issues)), review_reason="; ".join(issues)))
    if not records:
        raise ValueError("No input records.")
    index_rows = []
    for normalized, entry in sorted(index.items(), key=lambda pair: (-len(pair[1]["procedures"]), pair[0])):
        index_rows.append(dict(procedure_label=entry["label"], procedure_count=len(entry["procedures"]),
                               patient_count=len(entry["patients"]), source_note_count=len(entry["rows"]),
                               item_mention_count=entry["mentions"], invalid_key_note_count=len(entry["invalid_rows"]),
                               loop_recorder_term=int(bool(LOOP.search(entry["label"]))),
                               label_variants=" | ".join(sorted(entry["variants"])), review_category=""))
    output_dir.mkdir(parents=True, exist_ok=False)
    index_fields = ["procedure_label", "procedure_count", "patient_count", "source_note_count",
                    "item_mention_count", "invalid_key_note_count", "loop_recorder_term", "label_variants", "review_category"]
    write_csv(output_dir / "procedure_index.csv", index_fields, index_rows)
    write_csv(output_dir / "procedure_records.csv", list(records[0]), records)
    item_fields = ["source_row", "mrn", "procedure_date", "note_id", "item_number", "procedure_label",
                   "original_item", "needs_review", "review_reason"]
    write_csv(output_dir / "procedure_items.csv", item_fields, items_out)
    write_csv(output_dir / "procedure_extraction_review.csv", list(records[0]), [r for r in records if r["needs_review"]])
    print("Source notes: {}; procedure labels: {}; notes needing review: {}".format(
        len(records), len(index_rows), sum(r["needs_review"] for r in records)))
    print("Review reasons: " + str(dict(Counter(reason for r in records for reason in r["review_reason"].split("; ") if reason))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Original CSV containing full_note")
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    run(args.input, args.out_dir)


if __name__ == "__main__":
    main()
