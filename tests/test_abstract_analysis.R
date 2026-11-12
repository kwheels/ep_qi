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

# Revision codes alone do not qualify: a positive technique can come from either source.
baseline <- tibble(.key = c("a", "b", "c"), mrn = c("1", "2", "3"),
  procedure_date = as.Date(rep("2024-01-01", 3)), procedure_list = c("Lead Reposition", "New Implant ILR", "New Implant"),
  note_access_eligible = c(NA, NA, TRUE))
stopifnot(!abstract_cohort(baseline)$access_cohort_include[1])
baseline$micro_puncture_database <- c(TRUE, FALSE, FALSE)
stopifnot(abstract_cohort(baseline)$access_cohort_include[1])
stopifnot(!abstract_cohort(baseline, "exclude")$access_cohort_include[1])
stopifnot(!abstract_cohort(baseline)$access_cohort_include[2])
baseline$micro_puncture_database[1] <- NA
baseline$fluoroscopy_note <- c(TRUE, FALSE, FALSE)
stopifnot(abstract_cohort(baseline)$access_cohort_include[1])
baseline$fluoroscopy_note[1] <- FALSE
stopifnot(!abstract_cohort(baseline)$access_cohort_include[1])
baseline$note_access_eligible[1] <- FALSE
baseline$fluoroscopy_note[1] <- TRUE
stopifnot(!abstract_cohort(baseline)$access_cohort_include[1])

# Multiple PTX diagnosis dates assigned to the same procedure do not multiply rows.
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
