# Run from repository root: Rscript tests/test_note_merge.R
# Synthetic cases only; requires the R analysis dependencies.
suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(lubridate)
})
source("analysis/note_merge_helpers.R")

stopifnot(identical(normalize_mrn(c("00123", "123.0", "NULL", NA)), c("123", "123", NA_character_, NA_character_)))
stopifnot(identical(combine_access(c(TRUE, FALSE, NA, NA), c(FALSE, TRUE, FALSE, NA)), c(TRUE, TRUE, FALSE, NA)))
stopifnot(is.na(anything_counts(c(NA, NA))))
stopifnot(anything_counts(c(FALSE, TRUE)))
stopifnot(identical(as_access_flag(c("", "1", "0"), TRUE), c(FALSE, TRUE, FALSE)))
stopifnot(identical(fluoroscopy_without_venogram(
  c(TRUE, FALSE, TRUE, FALSE, NA, TRUE), c(TRUE, TRUE, FALSE, FALSE, FALSE, NA)),
  c(FALSE, FALSE, TRUE, FALSE, NA, NA)))

database <- tibble(
  mrn = c("00123", "123", "456", "789", "999", "1000", "NULL", "NULL"),
  procedure_date = as.Date(rep("2024-01-01", 8)),
  procedure_list = c("New Implant", "New Implant", "New Implant", "New Implant", "Generator Change", "New Implant", "New Implant", "New Implant"),
  procedure_source = c("MiHeart database", "Manual chart review", rep("MiHeart database", 6)),
  us = c(FALSE, TRUE, FALSE, FALSE, TRUE, NA, FALSE, FALSE),
  venogram = rep(FALSE, 8), micro_puncture = c(TRUE, FALSE, FALSE, FALSE, TRUE, NA, FALSE, FALSE),
  pouch = rep("Unknown", 8)
)
notes <- tibble(
  mrn = c("123", "456", "789", "999", "2000"),
  procedure_date = as.Date(rep("2024-01-01", 5)),
  note_access_rows = rep(1L, 5), note_eligibility_rows = rep(1L, 5),
  us_note = c(FALSE, TRUE, FALSE, TRUE, TRUE), venogram_note = rep(FALSE, 5),
  micro_puncture_note = c(FALSE, TRUE, TRUE, TRUE, TRUE), fluoroscopy_note = rep(TRUE, 5),
  note_access_eligible = c(TRUE, FALSE, NA, TRUE, TRUE)
)
result <- merge_note_documentation(database, notes)
data <- apply_access_eligibility(result$data)
stopifnot(nrow(data) == 7L, nrow(result$source_audit) == 8L, nrow(result$note_only) == 1L)
row123 <- filter(data, mrn == "123")
stopifnot(row123$database_row_count == 2L, row123$us, row123$micro_puncture, row123$access_cohort_include)
row456 <- filter(data, mrn == "456")
stopifnot(row456$us, row456$micro_puncture, !row456$access_cohort_include)
stopifnot(filter(data, mrn == "789")$access_cohort_include) # unresolved note keeps baseline decision
stopifnot(!filter(data, mrn == "999")$access_cohort_include) # pure generator code wins
row1000 <- filter(data, mrn == "1000")
stopifnot(!row1000$has_procedure_note, row1000$access_cohort_include, is.na(row1000$us), is.na(row1000$fluoroscopy))
stopifnot(sum(is.na(data$mrn)) == 2L) # invalid MRNs neither collapse nor match notes

# Synthetic on-disk reviewed CSV verifies that duplicate positives are not lost.
folder <- tempfile("cied_test_")
dir.create(folder)
access <- data.frame(phi_mrn = c("00123", "123"), proc_date = c("2024-01-01", "2024-01-01"),
                     ultrasound_used = c("", "1"), venogram_used = c("0", "0"),
                     micropuncture_used = c("1", "0"), fluoroscopy_used = c("", ""))
eligibility <- data.frame(mrn = "123", procedure_date = "2024-01-01", note_access_eligible = "1")
write.csv(access, file.path(folder, "access_technique_reviewed.csv"), row.names = FALSE)
write.csv(eligibility, file.path(folder, "procedure_eligibility.csv"), row.names = FALSE)
reviewed <- read_reviewed_notes(folder, file.path(folder, "procedure_eligibility.csv"))
stopifnot(nrow(reviewed) == 1L, reviewed$us_note, reviewed$micro_puncture_note, !reviewed$fluoroscopy_note)
message("Synthetic R note-merge checks passed.")
