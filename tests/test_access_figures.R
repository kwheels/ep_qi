# Synthetic checks of ggplot data, scales and exports; no clinical data.
source("analysis/access_figures.R")
synthetic <- data.frame(technique = c("Micropuncture", "Ultrasound", "Venogram"),
  n_used = c(100, 100, 0), n_not_used = c(100, 100, 200),
  ptx_used = c(1, 0, 0), ptx_not_used = c(3, 0, 0),
  pct_ptx_used = c(1, 0, NA), pct_ptx_not_used = c(3, 0, 0),
  p_value = c(0.3, NA, NA), sparse_expected_counts = TRUE)
stem <- tempfile("access_figure_")
panels <- write_access_figure(synthetic, stem, "Synthetic figure test")
stopifnot(length(panels) == 3, all(vapply(panels, inherits, logical(1), "ggplot")))
built <- ggplot2::ggplot_build(panels[[1]])
stopifnot(identical(as.character(built$data[[1]]$fill), c("#374E55", "#DF8F44")))
stopifnot(identical(as.numeric(built$data[[1]]$y), c(3, 1)))
stopifnot(all(built$data[[1]]$ymin == 0), all(built$data[[1]]$colour %in% NA))
stopifnot(identical(as.numeric(built$layout$panel_params[[1]]$y.range), c(0, 100)))
stopifnot(identical(panels[[1]]$labels$y, "Pneumothorax Rate (%)"))
stopifnot(file.info(paste0(stem, ".png"))$size > 1000, file.info(paste0(stem, ".pdf"))$size > 1000)
message("Synthetic ggplot figure checks passed.")
