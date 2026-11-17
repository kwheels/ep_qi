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
# Explicit aliases keep matching auditable; avoid unrestricted fuzzy matching.
ULTRASOUND_STANDARD = re.compile(r"(?:ultra[\s-]*sound|ultrasonograph\w*)", re.I)
ULTRASOUND_PATTERN = (
    r"\b(?:ultra[\s-]*sound|ultrasonograph\w*|"
    r"USG|U/S|US(?=[\s-]+(?:guided|guidance|guideance|guidence|guidiance)\b)|"
    r"ultrsound|ultrasoud|ultrasond|ultrasounnd|ultrsaound)\b"
)
TERMS = {
    "micropuncture": TERM,
    "ultrasound": re.compile(ULTRASOUND_PATTERN, re.I),
    "fluoroscopy": re.compile(
        r"\b(?:fluoro(?:scop\w*)?|fluroscop\w*|"
        r"x[\s\u2010-\u2015-]*ray[\s\u2010-\u2015-]+guid(?:ance|ed)|"
        r"radiographic[\s-]+guid(?:ance|ed))\b", re.I),
    "venogram": re.compile(r"\b(?:veno(?:gram\w*|graph\w*)|venous\s+angiograph\w*)\b", re.I),
    "cephalic_cutdown": re.compile(r"\bcephalic(?:\s+vein)?\s+cut[\s-]*down\b", re.I),
}
ACCESS = re.compile(
    r"\b(?:venous\s+access|vascular\s+access|access\s+(?:was\s+)?obtained|"
    r"(?:axillary|subclavian|cephalic|femoral|jugular)\s+vein|"
    r"venipuncture|cannulat\w*|punctur\w*|needle)\b", re.I)
GUIDANCE = re.compile(r"\b(?:guid\w*|using|under|with|performed|obtained)\b", re.I)
FEMORAL_SITE = re.compile(r"\b(?:femoral|groin)\b", re.I)
UPPER_SITE = re.compile(r"\b(?:axillary|subclavian)\b", re.I)


def ultrasound_site(context):
    """Local linkage only; upper access elsewhere cannot rescue femoral US."""
    femoral, upper = bool(FEMORAL_SITE.search(context)), bool(UPPER_SITE.search(context))
    if femoral and upper and re.search(
            r"\b(?:femoral\s+(?:and|/)\s+(?:axillary|subclavian)|"
            r"(?:axillary|subclavian)\s+(?:and|/)\s+femoral)\s+(?:venous\s+|vein\s+)?access\b", context, re.I):
        return "upper"
    return "mixed" if femoral and upper else "femoral" if femoral else "upper" if upper else "unspecified"
ACCESS_COURSE_CONTEXT = re.compile(
    r"\b(?:access|vein|venous|wire|needle|cannulat\w*|punctur\w*|cut[ -]*down)\b", re.I)
DIFFICULTY = re.compile(
    r"\b(?:attempt(?:ed|s)?|unsuccessful|failed|unable|difficult\w*|"
    r"tortuos\w*|spasm\w*|(?:would|could|did)\s+not\s+(?:advance|pass)|"
    r"resistance)\b", re.I)
CONVERSION = re.compile(
    r"\b(?:convert(?:ed|ing)?|switch(?:ed|ing)?|abandon(?:ed|ing)?|"
    r"(?:then\s+)?proceeded\s+to\s+(?:perform\s+)?(?:a\s+)?"
    r"cephalic(?:\s+vein)?\s+cut[ -]*down)\b", re.I)


def access_course(note):
    """Review signals only: do not infer which technique ultimately succeeded."""
    text = re.sub(r"\s+", " ", unicodedata.normalize("NFKC", note or "")).strip()
    sentences = [s.strip() for s in re.split(r"(?<=[.;!?])\s*", text) if s.strip()]
    difficulty, conversion = [], []
    for index, sentence in enumerate(sentences):
        if not ACCESS_COURSE_CONTEXT.search(sentence):
            continue
        # Include adjacent sentences so a failure following a technique is visible.
        evidence = " ".join(sentences[max(0, index - 1):index + 2])
        if DIFFICULTY.search(sentence):
            difficulty.append(evidence)
        if CONVERSION.search(sentence):
            conversion.append(evidence)
    return list(dict.fromkeys(difficulty)), list(dict.fromkeys(conversion))
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
    if technique == "ultrasound":
        # Keep list items/headings from sharing site context when whitespace is
        # collapsed. Wrapped narrative lines remain part of the same sentence.
        normalized = re.sub(r"\n\s*(?:[-*\u2022]|\d+[.)])\s+", "; ", normalized)
        normalized = re.sub(r"\n\s*[A-Z][A-Z /&-]{3,}:\s*", "; ", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()
    if not normalized:
        return "missing_note", "", 1, [], 0
    mentions = list(TERMS[technique].finditer(normalized))
    if not mentions:
        return "not_mentioned", "", 0, [], 0
    labels, evidence, sites = [], [], []
    for match in mentions:
        # Sentence boundaries deliberately exclude newlines (exported notes wrap).
        start = max(normalized.rfind(c, 0, match.start()) for c in ".;!?") + 1
        ends = [normalized.find(c, match.end()) for c in ".;!?"]
        end = min([p for p in ends if p >= 0] or [len(normalized)])
        before = normalized[max(start, match.start() - 120):match.start()]
        after = normalized[match.end():min(end, match.end() + 160)]
        context = before + match.group() + after
        coronary_venography = technique == "venogram" and (
            re.search(r"\b(?:coronary(?:\s+(?:sinus|venous))?|CS)\s*$", before, re.I) or
            re.search(r"^\s*(?:of|in)\s+(?:the\s+)?coronary(?:\s+sinus)?\b", after, re.I))
        if coronary_venography:
            label = "mention_without_access_context"
        elif technique != "micropuncture" and not ACCESS.search(context):
            label = "mention_without_access_context"
        elif NEGATIVE.search(before) or AFTER_NEGATIVE.search(after):
            label = "explicit_non_use"
        elif UNCERTAIN.search(context) or re.search(r"\bnot\b", context, re.I):
            label = "uncertain_mention"
        elif (ACTION.search(context) or
              (technique == "cephalic_cutdown" and re.search(r"\bperform(?:ed)?\b", context, re.I)) or
              (technique != "micropuncture" and GUIDANCE.search(context)) or
              (technique == "venogram" and re.search(r"\bfor\s+venous\s+access\b", context, re.I))):
            label = "documented_use"
        else:
            label = "uncertain_mention"
        if technique == "ultrasound":
            site = ultrasound_site(context)
            sites.append(site)
            if label in {"documented_use", "uncertain_mention"}:
                if site == "femoral":
                    label = "femoral_access_only"
                elif site == "mixed":
                    label = "uncertain_access_site"
        labels.append(label)
        evidence.append(context.strip())
    if technique == "ultrasound" and FEMORAL_SITE.search(normalized):
        # A generic summary ("ultrasound guidance for venous access") must not
        # override the body when its only site-specific US evidence is femoral.
        for index, site in enumerate(sites):
            if site == "unspecified" and labels[index] == "documented_use":
                if any(s == "upper" and label == "documented_use" for s, label in zip(sites, labels)):
                    continue
                labels[index] = ("femoral_access_only" if "femoral" in sites and not UPPER_SITE.search(normalized)
                                 else "uncertain_access_site")
    unique = set(labels)
    # Routine imaging elsewhere must not override a positive access sentence.
    relevant = unique - {"mention_without_access_context", "femoral_access_only"}
    status = (next(iter(relevant)) if len(relevant) == 1 else
              "mixed_mentions" if relevant else
              "femoral_access_only" if "femoral_access_only" in unique else "mention_without_access_context")
    value = {"documented_use": "1", "explicit_non_use": "0", "femoral_access_only": "0"}.get(status, "")
    variant = technique == "ultrasound" and any(
        not ULTRASOUND_STANDARD.fullmatch(match.group()) for match in mentions)
    course_review = any(access_course(normalized))
    review = int(variant or course_review or status in {"uncertain_mention", "mixed_mentions", "mention_without_access_context", "uncertain_access_site"})
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
        fields += ["ultrasound_matched_terms", "ultrasound_variant_match"]
        fields += ["access_difficulty_or_attempt", "access_conversion", "access_course_needs_review"]
        if args.include_evidence:
            fields += ["access_difficulty_evidence", "access_conversion_evidence"]
        # Exclusive creation prevents silently replacing an existing results file.
        with args.output.open("x", newline="", encoding="utf-8") as target:
            writer = csv.DictWriter(target, fieldnames=fields)
            writer.writeheader()
            for row_number, row in enumerate(reader, 1):
                if None in row or any(value is None for value in row.values()):
                    raise ValueError(f"Malformed CSV record {row_number}; check quoting/columns. Output is incomplete.")
                result = {name: row[name] for name in IDENTIFIERS if name in headers}
                result.update(input_row_number=row_number, needs_review=0, mention_count=0)
                difficulty, conversion = access_course(row[args.note_column])
                result["access_difficulty_or_attempt"] = int(bool(difficulty))
                result["access_conversion"] = int(bool(conversion))
                result["access_course_needs_review"] = int(bool(difficulty or conversion))
                result["needs_review"] = result["access_course_needs_review"]
                if args.include_evidence:
                    result["access_difficulty_evidence"] = " || ".join(difficulty)
                    result["access_conversion_evidence"] = " || ".join(conversion)
                ultrasound_terms = [m.group() for m in TERMS["ultrasound"].finditer(
                    unicodedata.normalize("NFKC", row[args.note_column]))]
                result["ultrasound_matched_terms"] = "; ".join(dict.fromkeys(ultrasound_terms))
                result["ultrasound_variant_match"] = int(any(
                    not ULTRASOUND_STANDARD.fullmatch(term) for term in ultrasound_terms))
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
