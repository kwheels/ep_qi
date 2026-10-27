#!/usr/bin/env python3
"""Extract documented micropuncture mentions from procedure-note CSVs.

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


def classify(note):
    """Conservative mention-level rules; these are documentation labels."""
    normalized = unicodedata.normalize("NFKC", note or "")
    normalized = re.sub(r"\s+", " ", normalized).strip()
    if not normalized:
        return "missing_note", "", 1, [], 0
    mentions = list(TERM.finditer(normalized))
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
        if NEGATIVE.search(before) or AFTER_NEGATIVE.search(after):
            label = "explicit_non_use"
        elif UNCERTAIN.search(context) or re.search(r"\bnot\b", context, re.I):
            label = "uncertain_mention"
        elif ACTION.search(context):
            label = "documented_use"
        else:
            label = "uncertain_mention"
        labels.append(label)
        evidence.append(context.strip())
    unique = set(labels)
    status = next(iter(unique)) if len(unique) == 1 else "mixed_mentions"
    value = {"documented_use": "1", "explicit_non_use": "0"}.get(status, "")
    review = int(status in {"uncertain_mention", "mixed_mentions"})
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
        fields += ["input_row_number", "access_technique", "micropuncture_status",
                   "micropuncture_used", "needs_review", "mention_count"]
        if args.include_evidence:
            fields.append("micropuncture_evidence")
        # Exclusive creation prevents silently replacing an existing results file.
        with args.output.open("x", newline="", encoding="utf-8") as target:
            writer = csv.DictWriter(target, fieldnames=fields)
            writer.writeheader()
            for row_number, row in enumerate(reader, 1):
                if None in row or any(value is None for value in row.values()):
                    raise ValueError(f"Malformed CSV record {row_number}; check quoting/columns. Output is incomplete.")
                status, value, review, evidence, mentions = classify(row[args.note_column])
                result = {name: row[name] for name in IDENTIFIERS if name in headers}
                result.update(input_row_number=row_number, access_technique="micropuncture",
                              micropuncture_status=status, micropuncture_used=value,
                              needs_review=review, mention_count=mentions)
                if args.include_evidence:
                    result["micropuncture_evidence"] = " || ".join(evidence)
                writer.writerow(result)
                counts[status] += 1
    print(f"Processed {sum(counts.values())} records.")
    for status, count in sorted(counts.items()):
        print(f"  {status}: {count}")


if __name__ == "__main__":
    main()
