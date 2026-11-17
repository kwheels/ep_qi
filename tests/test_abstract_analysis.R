# Synthetic checks; run from ep_qi with Rscript tests/test_abstract_analysis.R.
suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(stringr); library(lubridate); library(readr) })
source("analysis/note_merge_helpers.R")
source("analysis/abstract_helpers.R")

# Chi-squared test matches Pearson's uncorrected result, with explicit missingness.
d <- tibble(access = c(rep(TRUE, 10), rep(FALSE, 10), NA),
            pneumothorax = c(1, rep(0, 9), 1, 1, rep(0, 8), 0))
r <- access_chisquare(d, "access", "Test")
expected <- suppressWarnings(chisq.test(matrix(c(9, 1, 8, 2), nrow = 2, byrow = TRUE), correct = FALSE))
stopifnot(r$n_known == 20, r$n_missing == 1, isTRUE(all.equal(r$p_value, unname(expected$p.value))), r$sparse_expected_counts)
degenerate <- access_chisquare(tibble(access = c(TRUE, FALSE), pneumothorax = c(0L, 0L)), "access", "Test")
stopifnot(is.na(degenerate$p_value), grepl("Not estimable", degenerate$test_status))
stopifnot(identical(three_way_or(c(TRUE, FALSE, NA, FALSE, FALSE), c(FALSE, TRUE, FALSE, NA, FALSE)), c(TRUE, TRUE, NA, NA, FALSE)))

# Sensitivity subsets are independent and recalculate denominators/events.
sensitivity_input <- tibble(mrn = c("1", "1", NA, "2", "3", "4"),
  demographics_matched = c(TRUE, TRUE, FALSE, TRUE, FALSE, TRUE),
  has_procedure_note = c(TRUE, FALSE, FALSE, TRUE, TRUE, NA),
  pneumothorax = c(1L, 0L, 0L, 0L, 1L, 0L),
  micropuncture = c(TRUE, FALSE, FALSE, TRUE, TRUE, FALSE),
  ultrasound = c(FALSE, TRUE, FALSE, TRUE, FALSE, TRUE),
  venogram_or_fluoroscopy = c(TRUE, NA, NA, FALSE, TRUE, NA))
subsets <- access_sensitivity_cohorts(sensitivity_input)
stopifnot(nrow(subsets$completedemo) == 4, nrow(subsets$noteonly) == 3)
stopifnot("3" %in% subsets$noteonly$mrn, !"3" %in% subsets$completedemo$mrn)
subset_counts <- sensitivity_cohort_counts(subsets)
stopifnot(subset_counts$n_procedures_with_ptx[subset_counts$analysis == "completedemo"] == 1)
stopifnot(subset_counts$n_procedures_with_ptx[subset_counts$analysis == "noteonly"] == 2)
stopifnot(access_comparison_table(subsets$completedemo)$n_known[1] == 4)
stopifnot(all(is.na(access_comparison_table(sensitivity_input[FALSE, ])$p_value)))
split_input <- sensitivity_input
split_input$venogram <- c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE)
split_input$fluoroscopy_documented <- c(TRUE, FALSE, TRUE, TRUE, FALSE, NA)
split_results <- access_comparison_table(split_input, split_imaging = TRUE)
stopifnot(nrow(split_results) == 4)
stopifnot(split_results$n_used[split_results$technique == "Venogram"] == 2)
stopifnot(split_results$n_used[split_results$technique == "Fluoroscopy without venogram"] == 2)
stopifnot(split_results$n_missing[split_results$technique == "Fluoroscopy without venogram"] == 1)
coverage_input <- split_input
coverage_input$micropuncture <- c(TRUE, FALSE, FALSE, TRUE, TRUE, FALSE)
coverage <- note_access_coverage(coverage_input)
stopifnot(coverage$summary$n_note_procedures == 3)
stopifnot(coverage$summary$n_any_guidance_positive == 2)
stopifnot(coverage$summary$n_no_guidance_positive == 1)
stopifnot(coverage$review$mrn == "3", coverage$review$micropuncture)
stopifnot(nrow(coverage$no_technique_review) == 0)
no_technique_input <- coverage_input
no_technique_input$micropuncture <- FALSE
stopifnot(nrow(note_access_coverage(no_technique_input)$no_technique_review) == 1)
unknown_input <- coverage_input
unknown_input$fluoroscopy_documented[5] <- NA
stopifnot(note_access_coverage(unknown_input)$summary$n_no_guidance_with_unknown == 1)
stopifnot(sum(coverage$patterns$n_procedures) == coverage$summary$n_note_procedures)
coverage_input$cephalic_cutdown <- c(NA, NA, NA, NA, TRUE, NA)
cutdown_coverage <- note_access_coverage(coverage_input)
stopifnot(nrow(cutdown_coverage$review) == 0, nrow(cutdown_coverage$guidance_review) == 1)
stopifnot(cutdown_coverage$summary$n_no_guidance_but_cephalic_cutdown == 1)
stopifnot(cutdown_coverage$summary$n_any_guidance_or_cutdown_positive == 3)

# Revision codes alone do not qualify: a positive technique can come from either source.
baseline <- tibble(.key = c("a", "b", "c"), mrn = c("1", "2", "3"),
  procedure_date = as.Date(rep("2024-01-01", 3)), procedure_list = c("Lead Reposition", "New Implant ILR", "New Implant"),
  note_access_eligible = c(NA, NA, TRUE))
stopifnot(!abstract_cohort(baseline)$access_cohort_include[1])
baseline$micro_puncture_database <- c(TRUE, FALSE, FALSE)
stopifnot(abstract_cohort(baseline)$access_cohort_include[1])
stopifnot(!abstract_cohort(baseline, "exclude")$access_cohort_include[1])
stopifnot(!abstract_cohort(baseline)$access_cohort_include[2])
device_types <- baseline[rep(1, 3), ]
device_types$procedure_list <- c("New Implant Boston Scientific Sub-Q ICD", "New Implant EV ICD", "New Implant Extravascular ICD")
device_types$note_access_eligible <- NA
stopifnot(!any(abstract_cohort(device_types)$access_cohort_include))
baseline$micro_puncture_database[1] <- NA
baseline$fluoroscopy_note <- c(TRUE, FALSE, FALSE)
stopifnot(abstract_cohort(baseline)$access_cohort_include[1])
baseline$fluoroscopy_note[1] <- FALSE
stopifnot(!abstract_cohort(baseline)$access_cohort_include[1])
baseline$note_access_eligible[1] <- FALSE
baseline$fluoroscopy_note[1] <- TRUE
stopifnot(!abstract_cohort(baseline)$access_cohort_include[1])
baseline$note_access_eligible[1] <- NA
baseline$fluoroscopy_note[1] <- FALSE
baseline$cephalic_cutdown_note <- c(TRUE, NA, NA)
stopifnot(abstract_cohort(baseline)$access_cohort_include[1])

# Note-defined revision also requires positive access when MiHeart says new implant.
note_revision_case <- baseline[1, ]
note_revision_case$procedure_list <- "New Implant"
note_revision_case$note_eligibility_status <- "revision_requires_positive_access_flag"
note_revision_case$cephalic_cutdown_note <- FALSE
stopifnot(!abstract_cohort(note_revision_case)$access_cohort_include[1])
note_revision_case$us_note <- TRUE
stopifnot(abstract_cohort(note_revision_case)$access_cohort_include[1])

# Multiple PTX diagnosis dates assigned to the same procedure do not multiply rows.
assumption_input <- tibble(mrn = as.character(1:10), procedure_date = as.Date("2024-01-01"),
  has_procedure_note = TRUE, note_access_eligible = TRUE,
  note_qualifying_procedures = "Right ventricular lead insertion", us = FALSE, venogram = FALSE,
  fluoroscopy_documented = FALSE, micro_puncture = FALSE, cephalic_cutdown = NA,
  imaging_access_group = "Neither")
assumption_input$note_qualifying_procedures[3] <- "Lead insertion"
assumption_input$us[4] <- TRUE
assumption_input$has_procedure_note[5] <- FALSE
assumption_input$note_access_eligible[6] <- FALSE
assumption_input$micro_puncture[7] <- TRUE
assumption_input$fluoroscopy_documented[8] <- NA
assumption_input$venogram[9] <- TRUE
assumption_input$cephalic_cutdown[10] <- TRUE
assumed <- apply_scoped_fluoroscopy_assumption(assumption_input, assumption_input[-2, c("mrn", "procedure_date")])
stopifnot(identical(which(assumed$fluoroscopy_assumed), 1L), !any(assumed$fluoroscopy_documented %in% TRUE))
stopifnot(assumed$fluoroscopy_analysis[1], assumed$venogram_or_fluoroscopy[1], !assumed$fluoroscopy_analysis[2])
stopifnot(!any(apply_scoped_fluoroscopy_assumption(assumption_input, assumption_input[FALSE, c("mrn", "procedure_date")])$fluoroscopy_assumed))
tunnel_case <- baseline[1, ]
tunnel_case$note_tunneled_access <- TRUE
tunnel_case$note_tunneled_access_only <- TRUE
tunnel_case$note_access_eligible <- FALSE
tunnel_case$pneumothorax <- 1L
tunnel_result <- abstract_cohort(tunnel_case)
stopifnot(tunnel_result$tunneled_access, !tunnel_result$access_cohort_include, tunnel_result$pneumothorax == 1L)
tunnel_case$note_tunneled_access_only <- FALSE
tunnel_case$note_access_eligible <- TRUE
stopifnot(abstract_cohort(tunnel_case)$access_cohort_include)

ptx <- tibble(mrn = c("1", "1", "9"), date_diagnosed = c("01/02/2024", "01/03/2024", "01/03/2024"))
attached <- attach_ptx(baseline, ptx)
stopifnot(nrow(attached$data) == 3, attached$data$ptx_event_count[1] == 2L, nrow(attached$unmatched) == 1)

# Demographic joins preserve rows and do not use PTX-case demographics.
cohort <- tibble(mrn = c("1", "1", "2"), procedure_date = as.Date(c("2024-01-01", "2025-01-01", "2024-01-01")),
                 sex = c("old", "old", "old"), pneumothorax = c(0L, 1L, 0L))
demo <- tibble(mrn = "1", dob = as.Date("1950-06-01"), sex = "Female", race = "Example", ethnicity = "Example", medical_history = "Condition A | Condition A | Condition B")
joined <- add_demographics(cohort, demo)
stopifnot(nrow(joined) == 3, joined$age_at_procedure[1] == 73, is.na(joined$age_at_procedure[3]), joined$sex[1] == "Female")
patients <- joined %>% group_by(mrn) %>% slice_head(n = 1) %>% ungroup()
summary <- demographic_summary(patients, "patient")
stopifnot(summary$n == 2, summary$n_age_known == 1, summary$n_female == 1, summary$pct_female_known == 100)
inventory <- diagnosis_inventory(patients, joined)
stopifnot(nrow(inventory) == 2, all(inventory$n_patients == 1), all(inventory$n_procedures == 2))
schema <- schema_without_values(joined, "test")
stopifnot(!any(grepl("Female|1950|Condition A", unlist(schema))), nrow(schema) == ncol(joined))

# Header discovery, ambiguous field handling, and race long-table aggregation.
folder <- tempfile("abstract_synthetic_")
dir.create(folder)
dir.create(file.path(folder, "long"))
write_csv(tibble(MRN = c("001", "002"), PatientID = c("synthetic-a", "synthetic-b"),
                 PatientInfo__DOB = c("1950-06-01", "1960-01-01"), DemographicInfo__Sex = c("Female", "Male"),
                 ClarityMedicalHistory__ProblemDescription = c("Condition A", NA)), file.path(folder, "patients.csv"))
write_csv(tibble(MRN = c("001", "001"), RaceDescription = c("Example A", "Example B")), file.path(folder, "long/PatientRace.csv"))
candidates <- field_candidates(folder)
mapping <- suggest_field_map(candidates)
loaded <- load_demographic_fields(folder, mapping)$data
stopifnot(nrow(loaded) == 2, loaded$sex[1] == "Female", loaded$race[1] == "Example A | Example B")
stopifnot(is.na(parse_dob("21916")), parse_dob("21916", "excel") == as.Date("1960-01-01"))
stopifnot(parse_dob("1950-06-01") == as.Date("1950-06-01"))
dates <- c("01/01/1940 00:00", "02/15/1960 00:00", "12/19/1950 00:00", "07/04/1935 00:00",
           "6/1/1950 12:30:00 PM", "1950-06-01T00:00:00", "02/30/1950 00:00", "01/01/40")
stopifnot(identical(parse_dob(dates), as.Date(c("1940-01-01", "1960-02-15", "1950-12-19", "1935-07-04",
                                                       "1950-06-01", "1950-06-01", NA, NA))))
profile <- dob_format_profile(c("21916", "1950-06-01", NA))
stopifnot(sum(profile$n_rows) == 3, "numeric_text_possible_excel_serial" %in% profile$format)
oldmap <- tibble(variable = c("sex", "ethnicity", "race"), source_file = c(NA, NA, "patients.csv"),
                 column = c(NA, NA, "ManualSelection"), status = c("not identified", "not identified", "manual"))
newmap <- tibble(variable = c("sex", "ethnicity", "race"), source_file = rep("patients.csv", 3),
                 column = c("DemographicInfo__GenderName", "DemographicInfo__EthnicityName", "RaceName"))
fixedmap <- refresh_field_map(oldmap, newmap)
stopifnot(fixedmap$column[1] == "DemographicInfo__GenderName", fixedmap$column[3] == "ManualSelection")
write_csv(tibble(diagnosis_term = c("unreviewed raw text", "other"), reviewed_term = c("Approved condition", ""),
                 approved_for_sharing = c("yes", ""), n_patients = c(10, 1), n_procedures = c(12, 1), proposed_group = c("", "")),
          file.path(folder, "review.csv"))
export_reviewed_diagnoses(file.path(folder, "review.csv"), file.path(folder, "share.csv"))
shared <- read_csv(file.path(folder, "share.csv"), show_col_types = FALSE)
stopifnot(nrow(shared) == 1, !"diagnosis_term" %in% names(shared))
message("Synthetic abstract-analysis checks passed.")
