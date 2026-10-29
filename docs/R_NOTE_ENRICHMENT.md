# Preliminary note-enriched PTX analysis

Run from the repository root on Armis2:

```bash
git pull
Rscript tests/test_note_merge.R
Rscript analysis/ptx_analysis_v2.R
```

The new analysis is a copy of the supplied `ptx_analysis_v1.R` with note integration. The original local script is unchanged. Helpers live in `analysis/note_merge_helpers.R`. The analysis uses the original packages, including dplyr 1.1+ for `join_by()` and `logistf` for the original three-predictor Firth model. The helper test uses synthetic data and must be run in R; passing Python tests does not validate this R code.

## Inputs

Under `/home/kwheels/cied_complications`:

- `Micropuncture.xlsx`
- `manual_procedure_review.xlsx`
- `access_technique_reviewed.csv` (the human-reviewed 0/1 technique labels)
- `procedure_categories_v1/procedure_eligibility.csv`
- `ptx_patients_clean.csv`

The top of the R script defines `data_dir`, `eligibility_file` and `output_dir`. Existing procedure inventory/category folder names stay unchanged. Source files are read-only.

The reviewed access CSV is used directly instead of the consensus clean CSV: duplicate positive labels must survive the requested anything-counts rule, even if the prior comparison export left a conflicted consensus blank. Reviewed note blanks become FALSE as previously instructed. Unreviewed automatic status/evidence fields are not used to infer access. The currently saved procedure eligibility CSV is used as-is; no new eligibility categorization rules are applied in R.

## Merge and eligibility

MiHeart and manual records form the baseline cohort. Notes are left-joined by normalized MRN and exact procedure date. Procedures without notes remain in the baseline; notes without database matches are audited, not appended. Invalid/missing database MRNs remain as separate baseline rows, never match one another or note/PTX records, and are audited.

Valid duplicate MRN/date database records collapse to one procedure. Procedure descriptions and source labels are combined, techniques use anything-counts, and all original source access rows are retained in an audit. Conflicting unrelated metadata becomes NA instead of choosing an arbitrary source. Duplicate note labels also use anything-counts; contradictory note eligibility is unresolved rather than picking inclusion/exclusion.

Access-cohort eligibility is applied **after the existing PTX assignment**, so excluding a procedure does not silently reassign its PTX to an older procedure:

- A note eligibility value of 0 excludes the procedure from the access cohort.
- A note eligibility value of 1 establishes eligibility, except for pure generator-change codes in the original database.
- Missing or unresolved note eligibility uses the original database criteria: New Implant, Lead Revision, Lead Reposition, Upgrade/Downgrade or Lead Extraction, excluding database-coded leadless cases.
- Pure generator change/replacement/exchange codes are excluded. A database description also containing one of the qualifying original components is treated as a mixed case, not generator-only. Note-positive/database-generator-only disagreements remain in the audit.

Thus keeping a procedure without notes means it remains subject to the original analytical cohort rules, not that every baseline procedure enters the access cohort. Unresolved note cases retain that preliminary fallback and are exported for later adjudication.

## Anything-counts access flags

For US, venogram, micropuncture and fluoroscopy, a positive in any database or reviewed-note row yields TRUE. If no positive exists but a source documents FALSE, the result is FALSE. If all sources are unknown, the result stays NA. Source flags (`*_database`, `*_note`), discrepancies and `*_added_from_note` are retained.

Fluoroscopy is read only if a separately named database variable exists (`fluoroscopy`, `fluoro`, `fluoroscopy_used`, `fluoro_used`). Otherwise only reviewed-note fluoroscopy is available; it is not inferred from venography or absence of ultrasound. Access site/sequence is not newly adjudicated in this preliminary merge, so reviewed US/fluoroscopy positives can reflect other procedural access as already discussed. Fluoroscopy is added to the descriptive access comparison; the original Firth model remains US + venogram + micropuncture.

## Output folder

`/home/kwheels/cied_complications/analysis_note_enriched` is reused on reruns. Named generated CSVs are replaced; save adjudicated copies under different names.

- `procedure_access_crosscheck.csv`: baseline procedures with original and combined access values and note indicators.
- `database_source_access_audit.csv`: original database source-row access values.
- `database_duplicate_procedures.csv`: consolidated duplicate keys to review.
- `invalid_database_keys.csv`: unmatched invalid MRN/date baseline rows.
- `notes_without_database_match.csv`: note-only keys.
- `access_cohort_eligibility_audit.csv`: all baseline procedures, PTX outcomes and inclusion reasons.
- `excluded_access_procedures.csv`: excluded procedures, including any assigned PTX.
- `unresolved_note_eligibility.csv`: note-covered cases using the original database fallback.
- `note_enrichment_summary.csv`: coverage, exclusions and added positive access flags.
- `cied_analysis_access_enriched.csv`: preliminary cohort used by the downstream analysis.
- `ptx_access_light.csv`: updated anonymous access/PTX export.

All outputs except the aggregate summary and anonymous light export contain patient-level information. Keep them out of GitHub. Inspect the eligibility audit and excluded PTX cases before interpreting updated estimates; note coverage is incomplete and the enriched fields have not been validated as final adjudications.
