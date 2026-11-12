# Rebuild only the note access review using the saved procedure dataset.
# From ep_qi: Rscript analysis/review_note_access.R
suppressPackageStartupMessages({library(dplyr); library(readr)})
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
analysis_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]))) else "analysis"
source(file.path(analysis_dir, "note_merge_helpers.R"))
source(file.path(analysis_dir, "abstract_helpers.R"))
data_dir <- getOption("hrs.data_dir", "/home/kwheels/cied_complications")
output_dir <- getOption("hrs.output_dir", file.path(data_dir, "hrs_abstract_output"))
data <- read_csv(file.path(output_dir, "private/final_procedure_dataset.csv"), col_types = cols(.default = "c"), show_col_types = FALSE)
result <- note_access_coverage(data)
write_csv(result$review, file.path(output_dir, "private/noteonly_no_access_listed.csv"))
write_csv(result$summary, file.path(output_dir, "shareable/noteonly_access_coverage.csv"))
write_csv(result$patterns, file.path(output_dir, "shareable/noteonly_access_patterns.csv"))
print(result$summary, width = Inf)
