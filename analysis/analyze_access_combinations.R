# Refresh aggregate technique-combination tests from saved included procedures.
# Run from ep_qi: Rscript analysis/analyze_access_combinations.R
suppressPackageStartupMessages({library(dplyr); library(stringr); library(readr)})
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
analysis_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]))) else
  if (file.exists("analysis/abstract_helpers.R")) "analysis" else "."
source(file.path(analysis_dir, "note_merge_helpers.R"))
source(file.path(analysis_dir, "abstract_helpers.R"))
data_dir <- getOption("hrs.data_dir", "/home/kwheels/cied_complications")
output_dir <- getOption("hrs.output_dir", file.path(data_dir, "hrs_abstract_output"))
data <- read_csv(file.path(output_dir, "private/final_procedure_dataset.csv"),
                 col_types = cols(.default = "c"), show_col_types = FALSE)
data$pneumothorax <- as.integer(as_access_flag(data$pneumothorax))
data$has_procedure_note <- as_access_flag(data$has_procedure_note)
# Older saved final datasets include eligible procedures without notes.
data <- data %>% filter(has_procedure_note %in% TRUE)
if (!nrow(data)) stop("No eligible procedures with matched procedure notes in the saved dataset.")
data$demographics_matched <- as_access_flag(data$demographics_matched)
cohorts <- access_sensitivity_cohorts(data)
for (name in names(cohorts)) {
  suffix <- if (name == "full") "" else paste0("_", name)
  write_csv(access_combination_table(cohorts[[name]], split_imaging = name == "noteonly"),
            file.path(output_dir, "shareable", paste0("access_combination_chisquared", suffix, ".csv")))
}
message("Combination tables refreshed from the saved final procedure dataset; cohort eligibility and figures unchanged.")
