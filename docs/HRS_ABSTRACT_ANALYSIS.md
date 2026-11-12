# HRS abstract numerical analysis

This is a standalone analysis with three procedure-level Pearson chi-squared comparisons and **no Firth regression**. It rebuilds the cohort from the original databases, reviewed access labels and procedure eligibility. It does not source the older v2 analysis or require its regression section to run.

From the `ep_qi` root on Armis2:

```bash
git pull
Rscript tests/test_abstract_analysis.R
Rscript analysis/hrs_abstract_analysis.R
```

In RStudio, set the repository root as the working directory and run `analysis/hrs_abstract_analysis.R` section by section. R 4.5.1 and the existing dplyr/readr/readxl/stringr/tidyr/lubridate/janitor packages are required. Existing dplyr 1.1+ is sufficient; no newer R syntax is introduced. Local checks use R 4.6.1 and are not execution on Armis2 R 4.5.1.

## Inputs and output location

Defaults under `/home/kwheels/cied_complications`:

- `Micropuncture.xlsx` and `manual_procedure_review.xlsx`
- `access_technique_reviewed.csv`
- `procedure_categories_v1/procedure_eligibility.csv`
- `ptx_patients_clean.csv`
- `demographic_extraction_output/patients.csv` and its `long/` extracts

The reusable output folder is **`hrs_abstract_output`**. Generated outputs are replaced on rerun, except the editable `demographic_field_map.csv` and `private/diagnosis_terms_for_review.csv`, which are preserved. The refreshed diagnosis inventory is always written separately as `private/diagnosis_terms_generated.csv`. If inputs change, reconcile any edited diagnosis review file with that generated copy.

Override paths via `options()` before `source()` if needed:

```r
options(hrs.data_dir = "/home/kwheels/cied_complications")
options(hrs.output_dir = "/home/kwheels/cied_complications/hrs_abstract_output")
source("analysis/hrs_abstract_analysis.R")
```

## Eligibility and cohort unit

The MiHeart/manual database is the baseline. Valid duplicate MRN/date records collapse to one procedure with original rows audited. Notes are left-joined; patients without notes remain subject to database criteria. Note-only procedures are not added. PTX is matched within the existing 0–14-day post-procedure window and assigned to the most recent preceding procedure **before** exclusions. Multiple diagnosis dates assigned to one procedure count as one procedure with PTX; event counts are also reported.

Reviewed note eligibility 1 qualifies a permanent implant or attempted lead implant, while 0 excludes nonqualifying procedures. Temporary pacing/ILR/leadless items do not cancel a separate qualifying transvenous implant. Database-coded loop recorder, leadless and subcutaneous ICD procedures without a qualifying note are excluded. Generator-only exclusions use the previous MiHeart rule. Extraction-coded eligible cases remain explicitly labeled in the procedure-type table.

**Unconfirmed revision/reposition access is not proven by a database revision code.** Default `hrs.unconfirmed_revision_policy="retain"` preserves the prior preliminary database fallback and reports `included_unconfirmed_revision_access`. This does not establish that access was obtained. To require confirmation for those cases:

```r
options(hrs.unconfirmed_revision_policy = "exclude")
source("analysis/hrs_abstract_analysis.R")
```

Invalid-MRN database records stay separately in the procedure cohort/audit but cannot contribute to an identifiable unique-patient count or demographic merge. Counts report these explicitly; a final study patient N cannot be assumed complete if they remain. Unresolved note classifications use the previous database fallback and remain visible in the eligibility audit.

## Demographics and field mapping

The script writes `demographic_field_map.csv` in the output root and `shareable/field_candidates.csv`. It selects a demographic field only when its candidate column is unique, preferring the patient-level file. Ambiguous/unidentified fields remain blank; the analysis runs with missing summaries rather than choosing arbitrary columns. Check this map before interpreting demographics, edit `source_file` and `column` when necessary, and rerun. Paths are relative to `demographic_extraction_output`, e.g. `patients.csv` or `long/PatientRace.csv`; column names must match the extractor output.

DOB, sex, race, ethnicity and medical history are loaded from those mapped files. Conflicting DOB/sex values for one MRN become missing and are audited. Multiple race/ethnicity responses are combined as a multi-response string; the raw category table is provisional until categories are reviewed. Patient-level demographic summaries use each identifiable patient's **first included procedure**. Procedure-level summaries are also supplied and clearly labeled. Age is attained whole years from DOB on the procedure date; ages outside 0–120 are missing and audited. PTX-only age/sex/race fields are not used to describe the whole cohort.

Female percentage uses recognized sex labels (Female/F, Male/M and listed other/nonbinary/intersex labels). Numeric or unrecognized coding stays unmapped and is counted in the missing/unmapped denominator. Review `private/race_ethnicity_sex_categories.csv` before deciding on coding changes. Missing demographics do not remove patients from the cohort. Race/ethnicity counts use all identifiable patients as the denominator, including a missing category.

## Access and tests

Anything-counts documentation is retained for micropuncture and ultrasound. The third exposure is **venogram OR original documented fluoroscopy** (before exclusive-category recoding). TRUE in either makes the combined flag TRUE; both FALSE make it FALSE; otherwise it is unknown. This is an OR between two different techniques: a negative venogram flag alone cannot establish absence of fluoroscopy. Thus records without a note may have unknown combined exposure even when venogram is FALSE. They remain in the cohort and contribute to tests for their other known techniques. Each test's missing denominator is explicit. Original source flags remain available for audit.

Each technique is a separate used-vs-not-used 2x2 comparison against PTX. Techniques can overlap; the three rows are not mutually exclusive access strategies. `access_chisquared.csv` gives event counts, rates, known/missing denominators, Pearson statistic, unadjusted P value, and expected-count diagnostics. No Yates correction, regression, automatic Fisher substitution or multiple-testing adjustment is applied. If a marginal group is absent, the test is not estimable and its P value stays missing. Small expected counts are flagged because the asymptotic chi-squared approximation can be unreliable with rare PTX. Repeated procedures from one patient are not cluster-adjusted by these requested tests.

## Files for review and sharing

`shareable/` contains aggregate numerical outputs and metadata without individual values:

- `cohort_counts.csv`, `cohort_flow.csv`
- `demographics_summary.csv`
- `new_implant_revision_summary.csv`
- `access_chisquared.csv`
- **`final_dataset_schema.csv`**: every final variable name, class, missing count and distinct count; no values or examples.
- **`demographic_input_schema.csv`**: headers/storage classes and profiles of up to 1,000 rows per extracted input file. Input columns are intentionally read as character; the profile is not a full-file count.
- **`field_candidates.csv`**: source columns potentially containing required demographic fields.
- `analysis_definitions.txt` and `R_session_info.txt`

Start by sharing the three bold metadata files to refine mappings and diagnosis extraction. Individual values are deliberately omitted even for MRN, PatientID, dates and free text.

`private/` contains patient/procedure datasets, eligibility and PTX audits, missingness/metadata conflicts, and the raw category/diagnosis review tables. Keep these files in the research location. `diagnosis_terms_for_review.csv` inventories every unique pipe-separated **mapped medical-history term** among included identifiable patients, with patient/procedure counts. Other diagnosis tabs are profiled in the input schema and can be mapped in a later step. Diagnosis history does not establish device indication or that a condition existed before the procedure; ischemic/nonischemic cardiomyopathy and pacemaker-indication group definitions are deliberately deferred until terms/fields are reviewed.

Although the diagnosis inventory omits MRNs, dates and PatientIDs, descriptions are free text and could themselves contain identifiers. To prepare a reviewed term list, fill `reviewed_term` with a cleaned clinical label and `approved_for_sharing=yes` for each appropriate row. The exporter only writes those edited labels with aggregate counts (default minimum five patients) and optional proposed group, not the raw description:

```bash
Rscript analysis/export_reviewed_diagnoses.R /home/kwheels/cied_complications/hrs_abstract_output/private/diagnosis_terms_for_review.csv /home/kwheels/cied_complications/hrs_abstract_output/shareable/reviewed_diagnosis_terms.csv
```

## Synthetic validation

`tests/test_abstract_analysis.R` checks missing-aware OR, cohort policies, chi-squared results/degenerate tables, PTX assignment without row multiplication, patient-level demographics, header mapping, history counts and reviewed diagnosis export. `tests/test_abstract_runner.py` runs the complete script on synthetic workbooks and checks cohort retention, output creation and absence of individual fixture values in shareable files. Set `RSCRIPT` to your Rscript path to run this optional integration test. These checks are not validation of real diagnosis classification or final cohort adjudication.
