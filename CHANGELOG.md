# Changelog

## 2026-11-12

- Parse slash-formatted DOB timestamps explicitly, including minutes-only time strings, rather than guessing formats; invalid dates/two-digit birth years remain for review.

- Recognize GenderName/EthnicityName, refresh only unresolved automatic field maps, and add value-free DOB format diagnostics with explicit Excel-serial parsing support.

- Require at least one positive access-technique flag from database or notes to retain otherwise unresolved lead revision/reposition cases in the abstract cohort.

- Add standalone HRS abstract outputs: patient/procedure counts, mapped whole-cohort demographics, procedure types, three Pearson chi-squared access comparisons, value-free schemas and local diagnosis-inventory review. No Firth regression; uncertain revision policy and sparse expected counts are explicit.

- Skip non-patient Query Specifications export metadata before validating table headers, and record the skip in the sheet summary.

- Add optional hidden-password, in-memory decryption for demographic XLSX workbooks; preserve encrypted sources and keep passwords out of command arguments.

## 2026-11-10

- Add demographic workbook extraction with PatientInfo MRN mapping, automatic singleton/long-tab classification, collapsed medical history, and identifier/QC audits. Text MRNs retain leading zeros; conflicting mappings remain unresolved for review.

## 2026-10-29

- Make final fluoroscopy an exclusive "fluoroscopy without venogram" category, preserving raw and anything-counts documentation for audits.

- Add preliminary R analysis integrating reviewed note eligibility and anything-counts US/venogram/micropuncture/fluoroscopy documentation while retaining uncovered database procedures and source audits.

- Allow inventory/categorization reruns in fixed output directories, replacing generated CSVs while preserving unrelated files.

- Extract all duplicated procedure sections with additional heading boundaries to reduce narrative/discharge spillover.
- Add item categorization and MRN/date access eligibility: retain attempted lead implants and mixed cases with qualifying permanent implants; separate leadless, ILR, temporary pacing, generator and uncertain categories.
- Preserve missing-section exclusions and ambiguous classifications for review; leave final MiHeart/R filtering for a subsequent step.

- Organized implementation in `scripts/`, automated checks in `tests/`, and workflow guides in `docs/`.
- Kept compatibility entry points for previously shared root commands.
- Added shared dependency instructions and exclusions for research data, outputs and Python cache files.
- Existing tools cover access extraction, reviewed-label reconciliation, invalid-key review, compact discrepancy review and procedure inventories.
