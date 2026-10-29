# Clean reviewed labels and compare databases

## Compact discrepancy review

To make an existing comparison easier to review, without rerunning Excel matching:

```bash
python3 format_access_review.py \
  /home/kwheels/cied_complications/access_reconciliation_v2/access_comparison.csv \
  /home/kwheels/cied_complications/access_reconciliation_v2/discrepancies_easy_review.csv
```

This includes only procedures present in both groups and only techniques that disagree, conflict within duplicate rows, or cannot be fully compared. Each row is one procedure/technique. Notes, MiHeart and manual-review values appear side by side as `Used (1)`, `Not used (0)`, `Unknown`, `No record`, or an explicit conflict. Original row references identify source records. Fill `resolved_value` with 0 or 1 after adjudication, and optionally add `reviewer_comments`. No resolution is prefilled and this script does not apply edits to the analysis. One procedure can have multiple review rows. Import MRN as text in Excel to preserve leading zeros. The source comparison remains unchanged.

If an MRN/date is invalid, strict mode stops with the source record number. To continue with valid records while preserving invalid rows for review:

```bash
python3 reconcile_access.py --quarantine-invalid --out-dir /home/kwheels/cied_complications/access_reconciliation_v2
```

This writes `rejected_rows.csv` with source file, original row number, reason and all original fields. No MRN/date is guessed or replaced. These rows cannot be matched and are excluded from comparison counts; `summary.json` reports `invalid_key_rows`, counts by source and `input_review_required=1`. Comparisons are provisional until the rejected rows are corrected and the script rerun. A source with no valid records still stops the run. Invalid technique labels and structural/header errors still stop processing rather than being quarantined.

Run on Armis2 in `ep_qi`. Source files are never changed. The script reads the reviewed labels, not the automated status or evidence columns. It performs an exact MRN/date match, not a date-window match.

```bash
git pull
python3 -m pip install --user openpyxl
python3 reconcile_access.py --out-dir /home/kwheels/cied_complications/access_reconciliation_v1
```

The default input folder is `/home/kwheels/cied_complications`, containing:

- `access_technique_reviewed.csv`
- `Micropuncture.xlsx`
- `manual_procedure_review.xlsx`

`--out-dir` must be a new directory, preventing accidental overwrites. Use a new version suffix when rerunning. Excel reading requires `openpyxl`; the cleaning-only mode uses Python's standard library. The first sheet is read by default, consistent with `read_excel()` in the supplied R script. Select another with `--miheart-sheet` or `--manual-sheet` if necessary. Full file overrides are available via `--notes`, `--miheart`, and `--manual`. `--folder` changes the common input folder.

For cleaning alone:

```bash
python3 reconcile_access.py --clean-only --out-dir /home/kwheels/cied_complications/access_clean_v1
```

## Outputs

- `access_technique_clean.csv`: **only** `mrn,procedure_date,us,venogram,micro_puncture,fluoroscopy`. Reviewed note blanks become 0 as instructed. Values otherwise become 0/1. Identical duplicate procedure keys collapse. Conflicting duplicate technique values stay blank; see the source audit for the original values.
- `access_comparison.csv`: full outer union of procedure keys in the notes and either Excel database, one row per procedure. Keeps source presence, counts, per-source values, flags, candidate combined values and original source records.
- `access_comparison_review.csv`: the same columns, limited to `needs_review=1`.
- `source_records.csv`: every original row with its source file, row reference, match key, date, and all original fields serialized as JSON. This preserves conflicting originals even when consensus fields are blank. Includes original note evidence and original database fields, so it may contain PHI.
- `summary.json`: aggregate row counts, blank-to-zero counts and comparison counts. Console output is aggregate only.

Cleaning-only mode omits the comparison CSVs. All outputs contain patient identifiers except the aggregate summary. Keep them in the research data location; do not commit them to GitHub.

## Matching and flags

MRNs are read as text; leading zeros in the reviewed MRN are preserved in the output. The separate `mrn_match_key` strips leading zeros for cross-source matching, so `00123` matches Excel numeric `123`. This assumes leading zeros are formatting rather than distinct identifiers. Only digit MRNs are accepted; scientific notation and malformed dates/labels stop processing with source record references. Dates become `YYYY-MM-DD`. US-style month/day/year, ISO dates/timestamps, and actual Excel date cells are accepted. Unformatted Excel date serials are rejected rather than guessed.

Input column matching ignores case, spaces, underscores and punctuation, and recognizes the reviewed and R-script schema. Embedded whitespace in a quoted column name such as `fluor\noscopy_used` is handled. Unexpected or ambiguous headers stop processing. TRUE/FALSE and 0/1 are accepted, along with yes/no; invalid tokens stop processing. **Only reviewed-note blank cells become 0. Excel blanks remain unknown.**

- `in_notes`, `in_miheart`, `in_manual`, `in_database`: source-presence indicators.
- `in_both`: notes present and at least one Excel source present.
- `*_notes`, `*_miheart`, `*_manual`, `*_database`: consensus technique values within each source/group. The combined database includes both Excel files.
- `*_notes_values`, `*_database_values`: normalized values for all contributing rows, including conflicting duplicates. `notes_records`, `miheart_records`, and `manual_records` contain originals and row references, in the same order as their source rows.
- `*_notes_conflict`, `*_database_conflict`: both 0 and 1 occur within that source/group.
- `*_discrepancy`: for US, venogram and micropuncture, 1 for a known disagreement or conflicting source duplicates when both groups are present; 0 for fully known agreement; blank when unmatched or unknown prevents comparison.
- `any_discrepancy`: 1 if any of the three technique flags is 1; 0 only when all three comparisons are known and agree; otherwise blank. Check `comparison_incomplete` as well: a row may have a known discrepancy and other unknown comparisons.
- `duplicate_conflict`: any note/database technique conflict within duplicate keys. Includes note fluoroscopy conflicts.
- `comparison_incomplete`: both source groups present, but at least one technique lacks a complete consensus. A known value plus a missing value in duplicate rows remains incomplete.
- `needs_review`: unmatched procedure, source conflict, incomplete comparison or any discrepancy.

The unsuffixed `us`, `venogram`, `micro_puncture` and `fluoroscopy` columns are candidate consensus values. They stay blank on conflict or any unknown contributing values; no source wins automatically. Fluoroscopy comes only from notes and is not part of the three-technique discrepancy comparison. These columns are not final adjudications.

## R analysis integration

The supplied R analysis expects baseline fields such as `procedure_list`, plus `us`, `venogram`, and `micro_puncture` represented as TRUE/FALSE. The clean/comparison CSV is **not a replacement for that full cohort dataset**. After adjudicating discrepancies, join confirmed technique values to the original cohort by normalized MRN and procedure date, preserving all cohort/procedure/outcome fields and converting 0/1 to logical. Keep unresolved values as NA. Do not append the outer-union comparison directly to the analytical cohort: note-only procedures still need cohort eligibility validation. The supplied R script has not been modified.

## Checks

```bash
python3 -m unittest -v test_reconcile_access.py
```

Tests use synthetic records for date/MRN normalization, matching, missing values, cross-source disagreement, conflicting duplicates, no row multiplication, original-value preservation and end-to-end CSV/Excel processing.
