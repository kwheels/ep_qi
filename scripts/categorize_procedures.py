#!/usr/bin/env python3
"""Categorize inventory items and propose procedure-level access eligibility.

Python 3.6+, standard library. Labels are reviewable rules, not final cohort adjudication.
"""
import argparse
import csv
import re
import sys
from collections import Counter, defaultdict
from functools import partial
from pathlib import Path

try:
    from .reconcile_access import mrn_text, date_text, write_csv
except ImportError:
    from reconcile_access import mrn_text, date_text, write_csv
try:
    from .procedure_terms import SUBCUTANEOUS_ICD, EXTRAVASCULAR_ICD, TUNNELED_COMPONENT
except ImportError:
    from procedure_terms import SUBCUTANEOUS_ICD, EXTRAVASCULAR_ICD, TUNNELED_COMPONENT

write_csv = partial(write_csv, overwrite=True)


def has(pattern, text):
    return bool(re.search(pattern, text, re.I))


QUALIFYING = {"transvenous_pacemaker_implant", "transvenous_icd_implant", "transvenous_lead_insertion",
              "attempted_transvenous_lead_implant"}
REVIEW = {"other_review", "lead_revision_reposition_review", "nontransvenous_system_review"}


def categorize(label, original):
    text = original.lower()
    base = label.lower()
    # Device names in the original item must override a generic insertion label.
    if has(r"\b(?:leadless|aveir|micra)\b|\bAbbott\s+IPG\s+LSP\w*\b", text):
        return "leadless_pacemaker"
    if SUBCUTANEOUS_ICD.search(text):
        return "subcutaneous_icd"
    if EXTRAVASCULAR_ICD.search(text):
        return "extravascular_icd"
    if TUNNELED_COMPONENT.search(text):
        return "tunneled_nontransvenous_component"
    if has(r"\btemporar\w*\b|externalized", text) and has(r"pacemaker|pacing|\bppm\b", text):
        return "temporary_pacing"
    if has(r"loop\s*recorder|event[_ -]*recorder|\b(?:ilr|icm)\b|implantable\s+cardiac\s+monitor", text):
        return "ilr_insertion_removal"
    if has(r"sub[ -]?(?:q|cutaneous)|\b(?:s-icd|sq-icd|epicardial)\b", base):
        return "nontransvenous_system_review"
    if has(r"washcloth|shower|incision\s+(?:care|with)|do\s+not|no\s+driving|"
           r"heparin|cefazolin|home\s+monitoring|bruising|wound\s+activity|cxr\s+portable", base):
        return "nonprocedure_text_review"
    implant = r"\b(?:insert\w*|implant\w*|placement|deploy\w*)\b"
    lead = r"\blead\b|\blbbap\b|left\s+bundle\s+branch\s+pacing"
    if has(lead, base) and has(r"unsuccessful|failed|inability|unable|attempt", base) and (
            has(implant, base) or has(r"left\s+bundle\s+branch\s+pacing", base)):
        return "attempted_transvenous_lead_implant"
    if has(r"\b(?:planned|considered|recommend\w*)\b|\bnot\s+(?:performed|implanted|inserted)\b", base):
        return "other_review"
    if has(r"\blead\b", base) and has(implant, base) and not has(r"repair|extract|explant|remov|abandon", base):
        return "transvenous_lead_insertion"
    if has(r"generator", base):
        return "generator_only_or_change_miheart_check"
    if has(r"\b(?:pacemaker|ppm)\b", base) and has(implant, base):
        return "transvenous_pacemaker_implant"
    if has(r"\b(?:icd|defibrillator|crt-d)\b", base) and has(implant, base):
        return "transvenous_icd_implant"
    if has(r"\b(?:lead|pacemaker|icd|device)\b", base) and has(r"extract|explant|remov|abandon", base):
        return "device_or_lead_removal_only"
    if has(r"lead", base) and has(r"revision|reposition|repair", base):
        if has(r"\blead\b", base) and has(r"\brepair\w*\b", base):
            return "lead_repair_only"
        return "lead_revision_reposition_review"
    if has(r"\bep\s+study\b|electrophysiolog\w*\s+study|electrophysiologic\s+study|"
           r"ventricular\s+stimulation|programmed\s+stimulation|wenkebach", base):
        return "ep_study_or_stimulation"
    if has(r"venogram|venograph|ultrasound|\bus[ -]guided|fluoroscop|vascular\s+access|"
           r"perclose|vascade|hemostasis|interrogation|programming|envelope|tyrx|aigis|"
           r"cangaroo|mapping|echocardi|\btee\b|\bdft\b|threshold\s+test|cardioversion|"
           r"ablation|pocket|hematoma|nerve\s+block|pericardiocentesis|transfusion|biopsy|lithotripsy", base):
        return "adjunct_or_other_intervention"
    return "other_review"


def read_csv(path):
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def procedure_key(row):
    try:
        return (mrn_text(row["mrn"]).lstrip("0") or "0", date_text(row["procedure_date"]))
    except ValueError:
        return ("invalid-source-row-" + row["source_row"], row["procedure_date"])


def run(inventory, output):
    limit = sys.maxsize
    while True:
        try:
            csv.field_size_limit(limit)
            break
        except OverflowError:
            limit //= 10
    records = read_csv(inventory / "procedure_records.csv")
    items = read_csv(inventory / "procedure_items.csv")
    groups, index = defaultdict(list), {}
    for item in items:
        category = categorize(item["procedure_label"], item["original_item"])
        item["category"] = category
        item["qualifying_implant_item"] = int(category in QUALIFYING)
        groups[procedure_key(item)].append(item)
        key = (item["procedure_label"].casefold(), category)
        if key not in index:
            index[key] = dict(procedure_label=item["procedure_label"], category=category, procedures=set(), notes=set())
        index[key]["procedures"].add(procedure_key(item))
        index[key]["notes"].add(item["source_row"])
    record_groups = defaultdict(list)
    for row in records:
        record_groups[procedure_key(row)].append(row)
    cohort = []
    for key, note_rows in sorted(record_groups.items()):
        components = groups.get(key, [])
        categories = {i["category"] for i in components}
        qualifying = [i["procedure_label"] for i in components if i["category"] in QUALIFYING]
        all_missing = all("missing_procedures_section" in r["review_reason"] for r in note_rows)
        parsing_review = any(any(issue in r["review_reason"] for issue in [
            "missing_anesthesia_boundary", "empty_procedures_section", "unbulleted_section",
            "invalid_mrn_or_date", "interleaved_discharge_text_in_procedure_section"]) for r in note_rows)
        unknown = bool(categories & REVIEW) or "nonprocedure_text_review" in categories
        # Discharge instructions can contaminate a reconstructed list without
        # making an otherwise explicit leadless-only procedure ambiguous.
        clear_leadless_only = ("leadless_pacemaker" in categories and not parsing_review
                               and categories <= {"leadless_pacemaker", "adjunct_or_other_intervention",
                                                  "nonprocedure_text_review"})
        if clear_leadless_only:
            unknown = False
        revision_access_check = (not parsing_review and "lead_revision_reposition_review" in categories
                                 and categories <= {"lead_revision_reposition_review", "adjunct_or_other_intervention",
                                                    "device_or_lead_removal_only", "nonprocedure_text_review"})
        if revision_access_check:
            unknown = False
        clear_repair_only = (not parsing_review and "lead_repair_only" in categories
                             and categories <= {"lead_repair_only", "adjunct_or_other_intervention",
                                                "device_or_lead_removal_only", "nonprocedure_text_review"})
        if clear_repair_only:
            unknown = False
        tunneled = bool(categories & {"tunneled_nontransvenous_component", "subcutaneous_icd", "extravascular_icd"})
        tunneled_only = (tunneled and not parsing_review and categories <= {
            "tunneled_nontransvenous_component", "subcutaneous_icd", "extravascular_icd",
            "adjunct_or_other_intervention", "device_or_lead_removal_only", "nonprocedure_text_review",
            "generator_only_or_change_miheart_check"})
        if tunneled_only:
            unknown = False
        mention_subq = any(r.get("note_mentions_subcutaneous_icd") == "1" for r in note_rows)
        mention_ev = any(r.get("note_mentions_extravascular_icd") == "1" for r in note_rows)
        device_review = bool(qualifying) and (mention_subq or mention_ev or bool(categories & {"subcutaneous_icd", "extravascular_icd"}))
        if all_missing:
            eligible, status = 0, "excluded_missing_procedures_section"
        elif qualifying:
            eligible, status = 1, "qualifying_implant_documented"
        elif tunneled_only:
            eligible, status = 0, "excluded_tunneled_nontransvenous_only"
        elif clear_leadless_only:
            eligible, status = 0, "excluded_leadless_only"
        elif clear_repair_only:
            eligible, status = 0, "excluded_lead_repair_only"
        elif revision_access_check:
            # The R merge checks access flags from BOTH sources before deciding.
            eligible, status = "", "revision_requires_positive_access_flag"
        elif parsing_review or unknown or not components:
            eligible, status = "", "manual_review_needed"
        else:
            eligible, status = 0, "no_qualifying_implant_documented"
        cohort.append(dict(mrn=note_rows[0]["mrn"], mrn_match_key=key[0], procedure_date=note_rows[0]["procedure_date"],
                           note_access_eligible=eligible, eligibility_status=status,
                           qualifying_procedures=" | ".join(sorted(set(qualifying))),
                           categories=" | ".join(sorted(categories)),
                           all_procedures=" | ".join(sorted({i["procedure_label"] for i in components})),
                           has_ilr=int("ilr_insertion_removal" in categories),
                           has_leadless=int("leadless_pacemaker" in categories),
                           has_subcutaneous_icd=int("subcutaneous_icd" in categories),
                           has_extravascular_icd=int("extravascular_icd" in categories),
                           has_tunneled_access=int(tunneled), tunneled_access_only=int(tunneled_only),
                           note_mentions_subcutaneous_icd=int(mention_subq), note_mentions_extravascular_icd=int(mention_ev),
                           nontransvenous_device_needs_review=int(device_review),
                           nontransvenous_device_evidence=" || ".join(dict.fromkeys(r.get("nontransvenous_device_evidence", "") for r in note_rows if r.get("nontransvenous_device_evidence"))),
                           has_temporary_pacing=int("temporary_pacing" in categories),
                           has_attempted_lead_implant=int("attempted_transvenous_lead_implant" in categories),
                           generator_miheart_check=int("generator_only_or_change_miheart_check" in categories),
                           needs_review=int(parsing_review or unknown or device_review or (eligible == "" and not revision_access_check)),
                           review_reasons="; ".join(reason for condition, reason in [
                               (eligible == "" and not revision_access_check, "Eligibility unresolved"),
                               (parsing_review, "Section extraction needs review"),
                               (unknown, "Uncertain or nonprocedure item(s)"),
                               (device_review, "Mixed or historical nontransvenous ICD mention")]
                               if condition),
                           extraction_flags="; ".join(sorted({r["review_reason"] for r in note_rows if r["review_reason"]})),
                           source_rows="; ".join(r["source_row"] for r in note_rows)))
    if not cohort:
        raise ValueError("No procedure records in inventory.")
    output.mkdir(parents=True, exist_ok=True)
    index_rows = [dict(procedure_label=v["procedure_label"], category=v["category"],
                       qualifying_implant_item=int(v["category"] in QUALIFYING), procedure_count=len(v["procedures"]),
                       source_note_count=len(v["notes"]), reviewed_category="")
                  for _, v in sorted(index.items(), key=lambda pair: (-len(pair[1]["procedures"]), pair[0]))]
    write_csv(output / "categorized_procedure_index.csv",
              ["procedure_label", "category", "qualifying_implant_item", "procedure_count", "source_note_count", "reviewed_category"], index_rows)
    write_csv(output / "procedure_eligibility.csv", list(cohort[0]), cohort)
    write_csv(output / "procedure_eligibility_review.csv", list(cohort[0]), [r for r in cohort if r["needs_review"]])
    write_csv(output / "excluded_missing_sections.csv", list(cohort[0]),
              [r for r in cohort if r["eligibility_status"] == "excluded_missing_procedures_section"])
    item_fields = list(items[0]) if items else ["source_row", "mrn", "procedure_date", "note_id",
        "item_number", "procedure_label", "original_item", "needs_review", "review_reason",
        "category", "qualifying_implant_item"]
    write_csv(output / "categorized_items.csv", item_fields, items)
    print("Procedure eligibility: " + str(dict(Counter(r["eligibility_status"] for r in cohort))))
    print("Procedures needing review: " + str(sum(r["needs_review"] for r in cohort)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", type=Path)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    run(args.inventory, args.out_dir)


if __name__ == "__main__":
    main()
