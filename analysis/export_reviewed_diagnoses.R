# Export only manually approved, edited diagnosis terms; no raw text/identifiers.
suppressPackageStartupMessages({library(dplyr); library(readr)})
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
analysis_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]))) else "analysis"
source(file.path(analysis_dir, "abstract_helpers.R"))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2 || length(args) > 3) stop("Usage: Rscript analysis/export_reviewed_diagnoses.R INPUT.csv OUTPUT.csv [minimum_patients=5]")
if (normalizePath(args[1], mustWork = TRUE) == normalizePath(args[2], mustWork = FALSE)) stop("Input and output must differ.")
minimum <- if (length(args) == 3) as.integer(args[3]) else 5L
if (is.na(minimum) || minimum < 1) stop("Minimum patient count must be positive.")
result <- export_reviewed_diagnoses(args[1], args[2], minimum)
message("Exported ", nrow(result), " approved terms.")
