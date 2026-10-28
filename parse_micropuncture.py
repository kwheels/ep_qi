#!/usr/bin/env python3
"""Extract micropuncture, ultrasound, fluoroscopy and venogram access documentation.

Standard-library only; input and output stay on the machine running this script.
One output row per input row, including duplicate candidate reports.
"""
import argparse
import csv
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

TERM = re.compile(r"\bmicro[\s-]*puncture\b", re.I)
TERMS = {
    "micropuncture": TERM,
    "ultrasound": re.compile(r"\b(?:ultra[\s-]*sound|ultrasonograph\w*|US[ -]guided)\b", re.I),
    "fluoroscopy": re.compile(r"\b(?:fluoro(?:scop\w*)?|fluroscop\w*)\b", re.I),
    "venogram": re.compile(r"\b(?:veno(?:gram\w*|graph\w*)|venous\s+angiograph\w*)\b", re.I),
}
ACCESS = re.compile(
    r"\b(?:venous\s+access|vascular\s+access|access\s+(?:was\s+)?obtained|"
    r"(?:axillary|subclavian|cephalic|femoral|jugular)\s+vein|"
    r"venipuncture|cannulat\w*|punctur\w*|needle)\b", re.I)
GUIDANCE = re.compile(r"\b(?:guid\w*|using|under|with|performed|obtained)\b", re.I)
NEGATIVE = re.compile(
    r"\b(?:no|without)\s+(?:a\s+|an\s+)?(?:use\s+of\s+(?:a\s+)?)?$|"
    r"\b(?:did\s+not|never)\s+(?:use|utilize|employ)\s+(?:a\s+)?$", re.I)
AFTER_NEGATIVE = re.compile(
    r"^\s*(?:needle|kit|set|technique|access)?\s*(?:was|were|is)?\s*"
    r"(?:not\s+(?:used|utilized|employed)|avoided)\b", re.I)
UNCERTAIN = re.compile(
    r"\b(?:consider(?:ed)?|plan(?:ned)?|may|might|could|if|recommend(?:ed)?|"
    r"available|standby|prior|previous|histor(?:y|ical)|attempt(?:ed)?|"
    r"unsuccessful|failed|unable)\b", re.I)
ACTION = re.compile(
    r"\b(?:inserted|introduced|advanced|used|utilized|employed|accessed|"
    r"obtained|cannulated|entered|punctured|using|with)\b", re.I)
IDENTIFIERS = [
    "master_row_id", "index_procedure_id", "record_id",
    "redcap_repeat_instrument", "redcap_repeat_instance", "phi_mrn",
    "mrn_norm", "proc_date", "note_id", "procedure_date",
    "source_row_number", "date_diff_days", "n_candidate_reports",
]


def classify(note, technique="micropuncture"):
    """Conservative mention-level rules; these are documentation labels."""
    normalized = unicodedata.normalize("NFKC", note or "")
    normalized = re.sub(r"\s+", " ", normalized).strip()
    if not normalized:
        return "missing_note", "", 1, [], 0
    mentions = list(TERMS[technique].finditer(normalized))
    if not mentions:
        return "not_mentioned", "", 0, [], 0
    labels, evidence = [], []
    for match in mentions:
        # Sentence boundaries deliberately exclude newlines (exported notes wrap).
        start = max(normalized.rfind(c, 0, match.start()) for c in ".;!?") + 1
        ends = [normalized.find(c, match.end()) for c in ".;!?"]
        end = min([p for p in ends if p >= 0] or [len(normalized)])
        before = normalized[max(start, match.start() - 120):match.start()]
        after = normalized[match.end():min(end, match.end() + 160)]
        context = before + match.group() + after
        if technique != "micropuncture" and not ACCESS.search(context):
            label = "mention_without_access_context"
        elif NEGATIVE.search(before) or AFTER_NEGATIVE.search(after):
            label = "explicit_non_use"
        elif UNCERTAIN.search(context) or re.search(r"\bnot\b", context, re.I):
            label = "uncertain_mention"
        elif (ACTION.search(context) or
              (technique != "micropuncture" and GUIDANCE.search(context)) or
              (technique == "venogram" and re.search(r"\bfor\s+venous\s+access\b", context, re.I))):
            label = "documented_use"
        else:
            label = "uncertain_mention"
        labels.append(label)
        evidence.append(context.strip())
    unique = set(labels)
    # Routine imaging elsewhere must not override a positive access sentence.
    relevant = unique - {"mention_without_access_context"}
    status = (next(iter(relevant)) if len(relevant) == 1 else
              "mixed_mentions" if relevant else "mention_without_access_context")
    value = {"documented_use": "1", "explicit_non_use": "0"}.get(status, "")
    review = int(status in {"uncertain_mention", "mixed_mentions", "mention_without_access_context"})
    return status, value, review, list(dict.fromkeys(evidence)), len(mentions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--note-column", default="full_note")
    parser.add_argument("--encoding", default="utf-8-sig")
    parser.add_argument("--include-evidence", action="store_true",
                        help="Include matching note excerpts (may contain PHI).")
    args = parser.parse_args()
    if args.input.resolve() == args.output.resolve():
        parser.error("Input and output must be different files.")
    # Permit large narrative cells without third-party packages.
    limit = sys.maxsize
    while True:
        try:
            csv.field_size_limit(limit)
            break
        except OverflowError:
            limit //= 10
    counts = Counter()
    with args.input.open(newline="", encoding=args.encoding) as source:
        reader = csv.DictReader(source, strict=True)
        headers = reader.fieldnames or []
        if len(headers) != len(set(headers)):
            parser.error("Duplicate CSV column names.")
        if args.note_column not in headers:
            parser.error(f"Required note column missing: {args.note_column}")
        if not ({"phi_mrn", "mrn_norm"} & set(headers)):
            parser.error("Expected phi_mrn or mrn_norm column.")
        fields = [name for name in IDENTIFIERS if name in headers]
        fields += ["input_row_number", "access_technique", "needs_review", "mention_count"]
        for technique in TERMS:
            fields += [technique + "_status", technique + "_used",
                       technique + "_needs_review", technique + "_mention_count"]
            if args.include_evidence:
                fields.append(technique + "_evidence")
        # Exclusive creation prevents silently replacing an existing results file.
        with args.output.open("x", newline="", encoding="utf-8") as target:
            writer = csv.DictWriter(target, fieldnames=fields)
            writer.writeheader()
            for row_number, row in enumerate(reader, 1):
                if None in row or any(value is None for value in row.values()):
                    raise ValueError(f"Malformed CSV record {row_number}; check quoting/columns. Output is incomplete.")
                result = {name: row[name] for name in IDENTIFIERS if name in headers}
                result.update(input_row_number=row_number, needs_review=0, mention_count=0)
                used = []
                for technique in TERMS:
                    status, value, review, evidence, mentions = classify(row[args.note_column], technique)
                    result[technique + "_status"] = status
                    result[technique + "_used"] = value
                    result[technique + "_needs_review"] = review
                    result[technique + "_mention_count"] = mentions
                    result["needs_review"] |= review
                    result["mention_count"] += mentions
                    if value == "1":
                        used.append(technique)
                    if args.include_evidence:
                        result[technique + "_evidence"] = " || ".join(evidence)
                    counts[technique + ": " + status] += 1
                result["access_technique"] = "; ".join(used)
                writer.writerow(result)
    print(f"Processed {sum(counts.values()) // len(TERMS)} records.")
    for status, count in sorted(counts.items()):
        print(f"  {status}: {count}")


if __name__ == "__main__":
    main()
