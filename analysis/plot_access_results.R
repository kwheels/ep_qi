# Redraw figures from existing aggregate CSVs; no clinical inputs required.
# Run from repository root, or source interactively in RStudio.
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
analysis_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]))) else
  if (file.exists("analysis/access_figures.R")) "analysis" else "."
source(file.path(analysis_dir, "access_figures.R"))
data_dir <- getOption("hrs.data_dir", "/home/kwheels/cied_complications")
output_dir <- getOption("hrs.output_dir", file.path(data_dir, "hrs_abstract_output"))
shareable_dir <- file.path(output_dir, "shareable")
for (suffix in c("", "_completedemo", "_noteonly")) {
  label <- switch(suffix, "_completedemo" = "Eligible procedures with demographic linkage",
                  "_noteonly" = "Eligible procedures with procedure notes", "All eligible procedures")
  results <- read.csv(file.path(shareable_dir, paste0("access_chisquared", suffix, ".csv")),
                      stringsAsFactors = FALSE, check.names = FALSE)
  write_access_figure(results, file.path(shareable_dir, paste0("access_ptx", suffix)), label)
}
message("Figures saved in ", shareable_dir)
