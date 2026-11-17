# HRS abstract numerical outputs. Target: R 4.5.1, dplyr >= 1.1.
# Run from ep_qi: Rscript analysis/hrs_abstract_analysis.R
# In RStudio: setwd(repository root), then source/run this file section by section.
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(stringr); library(lubridate)
  library(readr); library(readxl); library(janitor)
})
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
analysis_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]))) else
  if (file.exists("analysis/note_merge_helpers.R")) "analysis" else "."
source(file.path(analysis_dir, "note_merge_helpers.R"))
source(file.path(analysis_dir, "abstract_helpers.R"))
source(file.path(analysis_dir, "access_figures.R"))

# Configuration: paths can be changed here or set via options() before source().
data_dir <- getOption("hrs.data_dir", "/home/kwheels/cied_complications")
output_dir <- getOption("hrs.output_dir", file.path(data_dir, "hrs_abstract_output"))
demographic_dir <- getOption("hrs.demographic_dir", file.path(data_dir, "demographic_extraction_output"))
eligibility_file <- getOption("hrs.eligibility_file", file.path(data_dir, "procedure_categories_v1/procedure_eligibility.csv"))
revision_policy <- getOption("hrs.unconfirmed_revision_policy", "access_flag") # "exclude" supported
dob_encoding <- getOption("hrs.dob_encoding", "auto") # set "excel" only after confirming Excel serial DOBs
private_dir <- file.path(output_dir, "private")
shareable_dir <- file.path(output_dir, "shareable")
dir.create(private_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(shareable_dir, recursive = TRUE, showWarnings = FALSE)

# 1. Merge baseline databases and reviewed notes. Do not require note coverage.
read_procedures <- function(filename, source) {
  read_excel(file.path(data_dir, filename)) %>% clean_names() %>% mutate(
    mrn = as.character(mrn), patient_key = as.character(patient_key),
    pouch = as.character(pouch), procedure_source = source)
}
main_database <- read_procedures("Micropuncture.xlsx", "MiHeart database")
manual_database <- read_procedures("manual_procedure_review.xlsx", "Manual chart review")
reviewed_notes <- read_reviewed_notes(data_dir, eligibility_file)
merged <- merge_note_documentation(bind_rows(main_database, manual_database), reviewed_notes)
baseline <- merged$data
write_csv(merged$source_audit, file.path(private_dir, "database_source_rows.csv"))
write_csv(merged$note_only, file.path(private_dir, "notes_without_database_match.csv"))

# 2. Assign PTX on the full baseline before eligibility exclusions. Collapse
# multiple diagnoses assigned to one procedure, avoiding row multiplication.
ptx_review <- read_csv(file.path(data_dir, "ptx_patients_clean.csv"),
                       col_types = cols(.default = "c"), show_col_types = FALSE) %>% clean_names()
ptx <- attach_ptx(baseline, ptx_review)
eligibility_audit <- abstract_cohort(ptx$data, revision_policy)
cohort <- eligibility_audit %>% filter(access_cohort_include) %>% mutate(
  micropuncture = as_access_flag(micro_puncture), ultrasound = as_access_flag(us),
  # Use original documented fluoroscopy before prior venogram-priority recoding.
  venogram_or_fluoroscopy = three_way_or(venogram, fluoroscopy_documented))
if (!nrow(cohort)) stop("No included procedures. Inspect eligibility audit and input files.")
write_csv(eligibility_audit, file.path(private_dir, "eligibility_audit.csv"))
write_csv(eligibility_audit %>% filter(
  note_subcutaneous_icd %in% TRUE | note_extravascular_icd %in% TRUE |
  note_subcutaneous_icd_mention %in% TRUE | note_extravascular_icd_mention %in% TRUE |
  access_eligibility_basis == "excluded_nontransvenous_database_type"),
  file.path(private_dir, "nontransvenous_icd_audit.csv"))
write_csv(eligibility_audit %>% filter(!access_cohort_include), file.path(private_dir, "excluded_procedures.csv"))
write_csv(ptx$assigned, file.path(private_dir, "ptx_assignments.csv"))
write_csv(ptx$unmatched, file.path(private_dir, "ptx_unmatched.csv"))
write_csv(ptx$multiple_candidates, file.path(private_dir, "ptx_multiple_candidate_procedures.csv"))

# 3. Identify demographic fields from headers; never use PTX-only demographics
# as a substitute for whole-cohort demographic ascertainment.
candidates <- field_candidates(demographic_dir)
write_csv(candidates, file.path(shareable_dir, "field_candidates.csv"))
map_file <- file.path(output_dir, "demographic_field_map.csv")
if (!file.exists(map_file)) write_csv(suggest_field_map(candidates), map_file)
field_map <- read_csv(map_file, col_types = cols(.default = "c"), show_col_types = FALSE)
field_map <- refresh_field_map(field_map, suggest_field_map(candidates))
write_csv(field_map, map_file)
demo <- load_demographic_fields(demographic_dir, field_map, dob_encoding)
write_csv(demo$dob_profile, file.path(shareable_dir, "dob_format_profile.csv"))
write_csv(demo$dob_qc, file.path(private_dir, "unparsed_dob_values.csv"))
if (nrow(demo$dob_qc)) warning("Some nonblank DOBs could not be parsed. Review shareable/dob_format_profile.csv and local unparsed_dob_values.csv before interpreting age.")
cohort <- add_demographics(cohort, demo$data)
write_csv(demo$issues, file.path(private_dir, "demographic_multivalue_qc.csv"))
write_csv(cohort %>% filter(age_invalid), file.path(private_dir, "invalid_ages.csv"))
write_csv(cohort, file.path(private_dir, "final_procedure_dataset.csv"))

# One demographic observation per identifiable patient, age at first included
# procedure. Procedure-level demographics are also supplied explicitly.
patients <- cohort %>% filter(!is.na(mrn)) %>% arrange(mrn, procedure_date) %>% group_by(mrn) %>% slice_head(n = 1) %>% ungroup()
write_csv(patients, file.path(private_dir, "final_patient_dataset.csv"))
flow <- eligibility_audit %>% count(access_eligibility_basis, access_cohort_include, name = "n_procedures")
counts <- tibble(
  baseline_source_rows = nrow(main_database) + nrow(manual_database),
  baseline_procedure_records = nrow(baseline), included_procedures = nrow(cohort),
  included_patients_with_valid_mrn = nrow(patients),
  included_procedures_missing_patient_identifier = sum(is.na(cohort$mrn)),
  identifiable_patients_with_multiple_included_procedures = sum((cohort %>% filter(!is.na(mrn)) %>% count(mrn))$n > 1),
  included_with_note = sum(cohort$has_procedure_note), included_without_note = sum(!cohort$has_procedure_note),
  included_with_demographics = sum(cohort$demographics_matched),
  included_unconfirmed_revision_access = sum(cohort$unconfirmed_revision_access),
  included_revisions_by_access_flag = sum(cohort$access_eligibility_basis == "included_revision_positive_access_flag"),
  excluded_revisions_without_access_flag = sum(eligibility_audit$access_eligibility_basis == "excluded_revision_no_positive_access_flag"),
  included_procedures_with_ptx = sum(cohort$pneumothorax),
  included_ptx_events = sum(cohort$ptx_event_count),
  pct_procedures_with_ptx = 100 * mean(cohort$pneumothorax),
  excluded_procedures_with_ptx = sum(eligibility_audit$pneumothorax[!eligibility_audit$access_cohort_include]),
  unmatched_ptx_events = nrow(ptx$unmatched), revision_policy = revision_policy)
write_csv(counts, file.path(shareable_dir, "cohort_counts.csv"))
write_csv(flow, file.path(shareable_dir, "cohort_flow.csv"))
write_csv(bind_rows(demographic_summary(patients, "Unique identifiable patients; first included procedure"),
                    demographic_summary(cohort, "Included procedures")), file.path(shareable_dir, "demographics_summary.csv"))

categorical <- bind_rows(lapply(c("sex", "race", "ethnicity"), function(column) {
  patients %>% transmute(variable = column, category = coalesce(.data[[column]], "Missing")) %>%
    count(variable, category, name = "n_patients") %>% mutate(pct_all_identifiable_patients = 100 * n_patients / max(1, nrow(patients)))
}))
# Raw demographic categories stay local until the field mapping is verified.
write_csv(categorical, file.path(private_dir, "race_ethnicity_sex_categories.csv"))
procedure_types <- cohort %>% group_by(procedure_group) %>% summarise(n_procedures = n(),
  n_identifiable_patients = n_distinct(mrn, na.rm = TRUE), n_ptx = sum(pneumothorax), .groups = "drop") %>%
  mutate(pct_procedures = 100 * n_procedures / nrow(cohort))
write_csv(procedure_types, file.path(shareable_dir, "new_implant_revision_summary.csv"))

# 4. Three requested procedure-level 2x2 Pearson chi-squared comparisons.
# Groups compare used vs not-used for each technique; techniques may overlap.
# No Firth model, no automatic switch to Fisher, no continuity correction.
access_results <- access_comparison_table(cohort)
write_csv(access_results, file.path(shareable_dir, "access_chisquared.csv"))

# Sensitivity restrictions are applied after the original PTX assignment and
# eligibility filtering. Recalculate every denominator and test in each subset.
sensitivity_cohorts <- access_sensitivity_cohorts(cohort)
write_csv(access_comparison_table(sensitivity_cohorts$completedemo),
          file.path(shareable_dir, "access_chisquared_completedemo.csv"))
write_csv(access_comparison_table(sensitivity_cohorts$noteonly, split_imaging = TRUE),
          file.path(shareable_dir, "access_chisquared_noteonly.csv"))
write_csv(sensitivity_cohort_counts(sensitivity_cohorts),
          file.path(shareable_dir, "access_sensitivity_cohort_counts.csv"))
if (getOption("hrs.make_figures", TRUE)) {
  write_access_figure(access_results, file.path(shareable_dir, "access_ptx"), "All eligible procedures")
  write_access_figure(access_comparison_table(sensitivity_cohorts$completedemo),
    file.path(shareable_dir, "access_ptx_completedemo"), "Eligible procedures with demographic linkage")
  write_access_figure(access_comparison_table(sensitivity_cohorts$noteonly, split_imaging = TRUE),
    file.path(shareable_dir, "access_ptx_noteonly"), "Eligible procedures with procedure notes")
}
note_coverage <- note_access_coverage(cohort)
write_csv(note_coverage$review, file.path(private_dir, "noteonly_no_access_listed.csv"))
write_csv(note_coverage$guidance_review, file.path(private_dir, "noteonly_no_guidance_listed.csv"))
write_csv(note_coverage$summary, file.path(shareable_dir, "noteonly_access_coverage.csv"))
write_csv(note_coverage$patterns, file.path(shareable_dir, "noteonly_access_patterns.csv"))
cephalic_summary <- sensitivity_cohorts$noteonly %>% summarise(
  n_note_procedures = n(), n_cutdown_known = sum(!is.na(cephalic_cutdown)),
  n_cutdown_used = sum(cephalic_cutdown %in% TRUE),
  n_cutdown_unknown = sum(is.na(cephalic_cutdown)),
  n_ptx_with_cutdown = sum(cephalic_cutdown %in% TRUE & pneumothorax == 1))
write_csv(cephalic_summary, file.path(shareable_dir, "cephalic_cutdown_summary.csv"))

# 5. Schemas contain names/classes/counts only: no values, DOBs, MRNs or examples.
schemas <- bind_rows(schema_without_values(cohort, "final_procedure_dataset"), schema_without_values(patients, "final_patient_dataset"))
write_csv(schemas, file.path(shareable_dir, "final_dataset_schema.csv"))
input_files <- c(file.path(demographic_dir, "patients.csv"), list.files(file.path(demographic_dir, "long"), "\\.csv$", full.names = TRUE))
input_schemas <- bind_rows(lapply(input_files[file.exists(input_files)], function(path) {
  sample <- read_csv(path, n_max = 1000, col_types = cols(.default = "c"), show_col_types = FALSE)
  schema_without_values(sample, basename(path))
}))
write_csv(input_schemas, file.path(shareable_dir, "demographic_input_schema.csv"))

# Medical history is a diagnosis-inventory starting point, not adjudicated device
# indication or confirmed pre-procedure comorbidity. Other diagnosis sheets can
# be mapped after reviewing the input schema.
terms_file <- file.path(private_dir, "diagnosis_terms_for_review.csv")
if (!file.exists(terms_file)) write_csv(diagnosis_inventory(patients, cohort), terms_file)
# Preserve the editable review file on rerun; refresh a separate generated copy.
write_csv(diagnosis_inventory(patients, cohort), file.path(private_dir, "diagnosis_terms_generated.csv"))

writeLines(capture.output(sessionInfo()), file.path(shareable_dir, "R_session_info.txt"))
writeLines(c(
  "R target: 4.5.1. No regression is fitted.",
  paste("Unconfirmed revision policy:", revision_policy),
  "Patient demographics use first included procedure; procedure demographics count each procedure.",
  "Patients without notes/demographics remain; missing denominators are explicit.",
  "Unknown access is not automatically FALSE; venogram/fluoroscopy is a three-valued OR.",
  "Chi-squared p-values are unadjusted; inspect sparse expected-count flags.",
  "Repeated procedures within patients are not cluster-adjusted by the requested chi-squared tests.",
  "Field maps require verification; race/ethnicity and diagnoses remain provisional until reviewed.",
  "Only the shareable subfolder omits individual values. Review free-text diagnosis terms locally before sharing."
), file.path(shareable_dir, "analysis_definitions.txt"))
print(counts, width = Inf)
print(access_results, width = Inf)
print(sensitivity_cohort_counts(sensitivity_cohorts), width = Inf)
message("Outputs saved under ", output_dir, "; verify demographic_field_map.csv before interpreting demographics.")
