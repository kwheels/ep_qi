# Changelog

## 2026-11-12

- Recover lead-insertion items from bounded duplicated sections containing interleaved discharge text, retaining extraction QC and explicit review reasons.

- Detect Sub-Q/S-ICD and extravascular/EV-ICD using full procedure items, scan full-note mentions for review, and audit exclusions/mixed cases in the R analysis.

- Carry optional manually reviewed cephalic cutdown flags into the R merge, revision evidence and access-coverage audits, with separate documented-use counts and unknown coverage.

- Recognize X-ray/radiographic access guidance as fluoroscopy and keep coronary/CS venography distinct from peripheral access venography.

- Add a private note-covered no-guidance review list and aggregate union/overlap counts, with a standalone exporter for existing analysis outputs.

- Split venogram and fluoroscopy-without-venogram in the note-covered sensitivity table; keep combined imaging in the full and demographic-linked comparisons.

- Add demographic-linked and procedure-note-covered sensitivity chi-squared tables with independently recalculated denominators and cohort/PTX counts.

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

## 2026-11-17

- Automatically exclude clear leadless-only implants despite discharge-text contamination; preserve extraction flags and review for uncertain additional interventions.

- Recognize Abbott IPG LSP and explicit leadless PROCEDURE headings; route uncomplicated revisions/repositions to automatic merged access-flag eligibility instead of manual review.

- Recognize Medtronic Aurora, DVEA3E4, EV240163 and EV-CD wording as extravascular ICD clues, preventing EV leads from qualifying as transvenous implants.

- Automatically exclude lead-repair-only procedures while retaining mixed cases with a separately documented qualifying implant.

- Make note ultrasound extraction site-aware: exclude femoral-only evidence, retain linked axillary/subclavian ultrasound, and flag uncertain site linkage with reviewable evidence.

- Add nested full-scale/zoomed PTX figures with event counts, percentages and Pearson p-values for all three abstract cohorts; support redrawing from aggregate CSVs.

- Restyle abstract figures to the requested minimalist 5-by-5-inch format: no gridlines, bold black axes/ticks, compact panels and 300-dpi PNG export.

- Refine nested figures with white backgrounds, larger insets, tighter paired bars, no unknown annotations, and explicit pneumothorax-rate labels on the full-scale axes only.

- Join x/y axes at zero and separate category labels from the baselines in both main panels and zoomed insets.
