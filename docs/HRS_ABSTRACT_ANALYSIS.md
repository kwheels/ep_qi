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

After updating Sub-Q/extravascular ICD recognition, regenerate `procedure_inventory_v1` and `procedure_categories_v1` before rerunning this analysis. Generic ICD-insertion labels may previously have been misclassified when the actual Sub-Q device name appeared after a colon. Updated note eligibility excludes device-only Sub-Q/EV cases and preserves separate qualifying transvenous implants in mixed cases for review. The R database-type filter also recognizes EV/extravascular ICD codes. `private/nontransvenous_icd_audit.csv` lists matched device-type flags, full-note mentions/evidence and the final inclusion decision. Old eligibility files lack these optional fields and will not gain corrected note classifications until regenerated.

The MiHeart/manual database is the baseline. Valid duplicate MRN/date records collapse to one procedure with original rows audited. Notes are left-joined; patients without notes remain subject to database criteria. Note-only procedures are not added. PTX is matched within the existing 0–14-day post-procedure window and assigned to the most recent preceding procedure **before** exclusions. Multiple diagnosis dates assigned to one procedure count as one procedure with PTX; event counts are also reported.

Reviewed note eligibility 1 qualifies a permanent implant or attempted lead implant, while 0 excludes nonqualifying procedures. Temporary pacing/ILR/leadless items do not cancel a separate qualifying transvenous implant. Database-coded loop recorder, leadless and subcutaneous ICD procedures without a qualifying note are excluded. Generator-only exclusions use the previous MiHeart rule. Extraction-coded eligible cases remain explicitly labeled in the procedure-type table.

**Revision/reposition without confirmed implant/access in the note requires a positive access-technique flag.** Default `hrs.unconfirmed_revision_policy="access_flag"` retains such a procedure only if ultrasound, micropuncture, venogram or fluoroscopy is positive in either database or available notes. FALSE/missing alone does not qualify. The audit adds `has_positive_access_flag` and a specific inclusion/exclusion reason; cohort counts report retained revisions and exclusions lacking a positive flag. This is the user's preliminary proxy for access; site and sequence remain unadjudicated. Explicit nonqualifying note eligibility and nontransvenous/generator-only exclusions are not overridden. To exclude all unresolved revisions even when a positive flag exists:

```r
options(hrs.unconfirmed_revision_policy = "exclude")
source("analysis/hrs_abstract_analysis.R")
```

Invalid-MRN database records stay separately in the procedure cohort/audit but cannot contribute to an identifiable unique-patient count or demographic merge. Counts report these explicitly; a final study patient N cannot be assumed complete if they remain. Other unresolved note classifications use the previous database fallback and remain visible in the eligibility audit. Previously set R options with `hrs.unconfirmed_revision_policy="retain"` must be removed or changed to `"access_flag"`.

## Demographics and field mapping

`GenderName` and `EthnicityName` are recognized. On rerun, only previously blank automatic mappings marked `not identified`/`ambiguous` are filled when a unique candidate is newly available; existing selections are preserved. `shareable/dob_format_profile.csv` reports date-format patterns and string lengths without DOB values. Numeric text is not passed to the generic calendar-date parser. If the source is confirmed to contain Excel serial dates, set `options(hrs.dob_encoding="excel")` before sourcing the analysis (Excel 1900-date-system origin 1899-12-30); otherwise keep `"auto"`. Unparsed raw DOBs remain in `private/unparsed_dob_values.csv` for local inspection. Do not share that patient-level file.

DOB calendar text is parsed explicitly as ISO `YYYY-MM-DD` or US `MM/DD/YYYY`, accepting a trailing time of day (including minutes-only timestamps). Time is discarded for DOB. Invalid dates and two-digit birth years remain unparsed for review rather than guessing a century. The supplied DOB-format report showed slash-date strings, so keep `hrs.dob_encoding="auto"` for this dataset.

The script writes `demographic_field_map.csv` in the output root and `shareable/field_candidates.csv`. It selects a demographic field only when its candidate column is unique, preferring the patient-level file. Ambiguous/unidentified fields remain blank; the analysis runs with missing summaries rather than choosing arbitrary columns. Check this map before interpreting demographics, edit `source_file` and `column` when necessary, and rerun. Paths are relative to `demographic_extraction_output`, e.g. `patients.csv` or `long/PatientRace.csv`; column names must match the extractor output.

DOB, sex, race, ethnicity and medical history are loaded from those mapped files. Conflicting DOB/sex values for one MRN become missing and are audited. Multiple race/ethnicity responses are combined as a multi-response string; the raw category table is provisional until categories are reviewed. Patient-level demographic summaries use each identifiable patient's **first included procedure**. Procedure-level summaries are also supplied and clearly labeled. Age is attained whole years from DOB on the procedure date; ages outside 0–120 are missing and audited. PTX-only age/sex/race fields are not used to describe the whole cohort.

Female percentage uses recognized sex labels (Female/F, Male/M and listed other/nonbinary/intersex labels). Numeric or unrecognized coding stays unmapped and is counted in the missing/unmapped denominator. Review `private/race_ethnicity_sex_categories.csv` before deciding on coding changes. Missing demographics do not remove patients from the cohort. Race/ethnicity counts use all identifiable patients as the denominator, including a missing category.

## Access and tests

### Cephalic cutdown

The access parser already recognizes `cephalic vein cutdown` and `cephalic vein cut-down`. To carry adjudicated findings into R, append **`cephalic_cutdown_used`** to `access_technique_reviewed.csv`: 1 for documented use, 0 for reviewed non-use, blank for unreviewed/unknown. The column is optional for older reviewed files. Unlike the four existing reviewed technique columns, blanks in this newly added field remain unknown. Existing reviewed access labels are preserved; a new automated extract must not replace manual edits.

R retains `cephalic_cutdown_note`, `cephalic_cutdown_database` (if a database field exists), combined `cephalic_cutdown`, and corresponding source discrepancy/addition flags. Positive cutdown can provide access evidence for otherwise unresolved revisions. It does not override explicit nonqualifying note eligibility. The four existing note-only imaging/needle comparison rows stay the same; separate `shareable/cephalic_cutdown_summary.csv` reports documented use, unknown coverage and PTX counts.

Coverage reports now distinguish no imaging guidance from no recognized access route/guidance: `private/noteonly_no_guidance_listed.csv` retains all cases without ultrasound/venogram/fluoroscopy positives, including documented cutdowns; `private/noteonly_no_access_listed.csv` omits known cutdown cases from that review queue. Micropuncture-only cases still need guidance/route review. `noteonly_access_coverage.csv` separately counts cutdown cases and the union of imaging guidance or cutdown. Fluoroscopy used only to confirm wires after cutdown is not automatically needle-access fluoroscopy. Rerun the main analysis after editing the reviewed CSV; the standalone review exporter only reads the previously saved dataset.

To investigate note-covered procedures with no ultrasound/venogram/fluoroscopy listed, run `Rscript analysis/review_note_access.R` after an analysis run. This reads the saved final procedure CSV without rerunning the full analysis. It writes the private no-guidance/no-access review files described above, `shareable/noteonly_access_coverage.csv` (union/overlap/missingness counts), and `shareable/noteonly_access_patterns.csv` (observed guidance/cutdown combinations and PTX counts). These are also generated by the main script. No positive guidance means none of the three imaging flags is TRUE; all-FALSE and unknown cases are distinguished. Micropuncture alone still appears in the review because it does not identify imaging guidance or a surgical route. Ultrasound can overlap either imaging group, so summing individual technique counts is not the number of unique covered procedures. The review does not establish that venous access was absent and does not exclude additional records.

Two sensitivity tables are generated alongside the full-cohort `access_chisquared.csv`:

- `access_chisquared_completedemo.csv`: included procedures with a valid MRN and a successful demographic linkage. This excludes the currently identified missing-MRN records. It does not additionally require complete race, ethnicity, age or sex fields.
- `access_chisquared_noteonly.csv`: included procedures with `has_procedure_note=TRUE`. This is independent of the demographic restriction, not an additional filter layered onto it. Uses the same combined database-plus-note access flags; it does not switch to note-only exposure values. This file has four rows: micropuncture, ultrasound, venogram, and fluoroscopy without venogram. Venogram takes priority when both imaging techniques are documented, so those last two positive groups do not overlap. Each row uses its own used-vs-not-used chi-squared comparison against PTX. The full and demographic-linked files keep the combined venogram/fluoroscopy row.

Both recalculate their chi-squared comparisons with newly calculated denominators. PTX assignment is preserved from the full baseline and is not redone after subsetting. `access_sensitivity_cohort_counts.csv` gives procedure counts, unique identifiable patients, PTX counts/rates, note coverage and demographic linkage for full/completedemo/noteonly. The full cohort remains available; missing exposure values are handled separately for each test. Empty subsets or degenerate tables produce missing P values rather than errors.

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

## Abstract figures

The main script writes `access_ptx`, `access_ptx_completedemo`, and `access_ptx_noteonly` as vector PDF and 300-dpi PNG in the existing shareable folder. Each technique compares used vs not-used, with a full 0-100% view and a nested PTX-rate detail. All insets within a figure share a scale. Labels show raw PTX events/total procedures and percentages; group N and unknown exclusions are explicit. The p-values are taken directly from the matching aggregate CSV (unadjusted Pearson, no continuity correction); an asterisk flags sparse expected counts, not significance. Techniques may overlap. Figures inherit the exact cohort/denominator restrictions of their CSVs. No patient identifiers are plotted.

To redraw existing aggregate results without rerunning analysis: `Rscript analysis/plot_access_results.R`. In RStudio, set the existing `hrs.output_dir` option if needed, then source that script. Named figures are replaced on rerun. Set `options(hrs.make_figures=FALSE)` to skip figures in the main analysis. Rendering uses ggplot2 >= 3.4.0 (compatible with R 4.5.1) and standard grid for panel composition. If needed, run `install.packages("ggplot2")` once. Optional style overrides: `options(hrs.figure_colors=c("#374E55", "#DF8F44"), hrs.figure_family="sans")`; colors are ordered not-used, used. Keep built-in PDF font families for portable export.

Figure styling: fixed 5 x 5 inches (1500 x 1500 PNG pixels at 300 dpi), compact two-column panels, white background, no gridlines, bold black axes/ticks and tick labels. PDF exports use the same physical size. Three-technique figures use the fourth quadrant for definitions; note-only figures use all four panels.

The full-scale panels have white backgrounds, with no pale full-height column fills. Zoomed insets are enlarged and paired bars are spaced tightly. Unknown-count annotations are omitted from figures (the CSV retains missing counts). Only the larger panels carry the y-axis label "Pneumothorax Rate (%)"; insets retain numeric ticks without a heading.

Both main and inset x-axis baselines join the y-axis at zero; category labels sit below the ticks with explicit spacing.

All charts are ggplot2 objects; grid only arranges their grobs on the page. Default colors are the first two entries of the ggsci JAMA-inspired palette (not-used #374E55; used #DF8F44), embedded as hex values so ggsci itself is not required. Palette source: https://github.com/nanxstats/ggsci/blob/master/R/palettes.R . The shared zero-expansion scales align the axes at zero, and bars have no outlines.

Figure refinements: x-label margin is 2.5 pt, enlarged insets, and p-values are separate text annotations inside each full-scale plot.

For QC among included note-covered procedures, `private/noteonly_no_access_listed.csv` has no positive ultrasound, venogram, fluoroscopy or cutdown, but may have micropuncture. The stricter `private/noteonly_no_technique_listed.csv` additionally requires no positive micropuncture flag. Both use merged database/note flags and retain unknowns for review; absence of a positive flag does not prove non-use. `private/noteonly_no_guidance_listed.csv` also includes cephalic cutdown cases. Run the main analysis, or `Rscript analysis/review_note_access.R` to refresh QC lists from saved final data without redoing the analysis.

## Export selected cases without RStudio

Run `python3 scripts/export_analysis_cases.py` from the repository root. It reads the existing final procedure dataset and writes `qc_eligibility_cases.csv` (database references 659, 1884, 747, 1146), `qc_ptx_no_access_cases.csv` (2630, 2007), and `qc_case_export_status.csv` in the existing private folder. Matching uses complete semicolon-separated database row references, not substring matches. All original columns and string identifiers are retained, with matched references added. The status file explicitly reports missing references; absence does not establish the exclusion reason. Defaults correspond to the reviewed snapshot: row references may change if source inputs change. Optional input path, `--out-dir`, `--eligibility-rows` and `--ptx-rows` allow reuse. Named exports are overwritten on rerun; input remains unchanged. These exports contain patient identifiers and stay private. Import MRNs as text in Excel to retain leading zeros.

## Scoped fluoroscopy assumptions and tunneled procedures

The first updated main-analysis run preserves MRN/date membership from the existing `private/noteonly_no_access_listed.csv` in `private/fluoroscopy_assumption_subset.csv`. That snapshot is not overwritten or expanded on later runs. An alternative saved subset path can be provided via `options(hrs.fluoroscopy_assumption_subset=...)`. Without an existing subset, no assumptions are applied on that run. Only matching included, note-covered, note-eligible cases with specific atrial/right-ventricular/left-ventricular lead insertion and all three guidance flags explicitly FALSE qualify. Positive micropuncture or cephalic cutdown prevents the assumption. Generic lead insertion alone does not qualify.

`fluoroscopy_assumed` is separate from unchanged documented/source flags. `fluoroscopy_analysis` combines documented and assumed use and feeds composite/split comparisons, figures and coverage QC. `private/fluoroscopy_assumption_audit.csv` retains every matched included candidate, including those not inferred. Cohort counts/comparison tables and figure captions report the inference count. This is an analysis assumption, not recovered documentation.

The categorizer recognizes Sub-Q/subcutaneous lead, coil and array descriptions and models 6996S/6996SQ before generic lead-insertion rules. It writes `has_tunneled_access` (broad nontransvenous/tunneled-component group including Sub-Q and EV ICDs) and `tunneled_access_only`. R carries these as note flags plus `tunneled_access`, automatically excludes tunneled-only cases, and saves all flagged procedures in `private/tunneled_access_audit.csv`, retaining PTX outcomes for separate review. A separate qualifying transvenous implant is retained with the mixed-case flag. These flags classify procedural components, not PTX causation. Regenerate Python inventory/categories before R to incorporate new model recognition; source access CSV corrections remain separate.

## Access-technique combinations

Three additional shareable tables are generated by the main analysis: `access_combination_chisquared.csv`, `access_combination_chisquared_completedemo.csv`, and `access_combination_chisquared_noteonly.csv`. To generate just these tables from the existing final procedure dataset, run `Rscript analysis/analyze_access_combinations.R` from the repository root. This does not recalculate eligibility, PTX assignment, source flags, or figures. Existing aggregate combination tables are replaced. Paths use the same hrs.data_dir/hrs.output_dir options as the main analysis.

Each table includes both definitions:

- **At least these techniques:** every specified technique is positive; additional techniques are permitted. Micropuncture + ultrasound thus includes cases also receiving imaging. Every feasible pair and higher-order combination is compared against procedures where at least one specified technique is known FALSE. If no component is FALSE and at least one is unknown, the combination is unknown and excluded from that comparison.
- **Exact pattern:** only the listed techniques are positive; all other considered techniques are FALSE. These mutually exclusive patterns (including singles and None documented) require all component flags to be known. Each pattern is compared against all other complete patterns. None documented means no recorded positive flag among the considered techniques, not proven non-use.

Full and demographic-linked cohorts consider micropuncture, ultrasound, and composite venogram/fluoroscopy: four inclusive combinations and eight exact patterns. The note-covered cohort splits venogram from fluoroscopy without venogram: five inclusive pairs, two inclusive triples, and twelve feasible exact patterns. Impossible venogram-plus-exclusive-fluoroscopy patterns are omitted. Cephalic cutdown is not added to these tests; its existing separate summary is retained. The original single-technique tables and all figures are unchanged.

`n_used`/`ptx_used`/`pct_ptx_used` describe the combination/pattern group; `n_not_used` and corresponding fields describe its comparator. Missing counts, sparse expected counts, and non-estimable tests remain explicit. Tests are unadjusted Pearson chi-squared without continuity correction, as in the single-technique analysis. `p_value_bh` supplements the raw `p_value`, with Benjamini-Hochberg adjustment separately within each definition in each cohort table. These exploratory comparisons overlap and are not independent; sparse rare-event tests require cautious interpretation. `n_fluoroscopy_assumed_in_group` reports group members carrying the scoped assumption, without changing original documentation.
