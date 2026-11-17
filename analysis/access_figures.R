# Nested PTX frequency figures from aggregate comparison tables. R 4.5.1+;
# base graphics only. No patient-level data are needed by this renderer.
write_access_figure <- function(results, output_stem, cohort_label,
                                colors = getOption("hrs.figure_colors", c("#727C89", "#176B87")),
                                family = getOption("hrs.figure_family", "sans")) {
  required <- c("technique", "n_used", "n_not_used", "ptx_used", "ptx_not_used",
                "pct_ptx_used", "pct_ptx_not_used", "p_value", "n_missing", "sparse_expected_counts")
  stopifnot(all(required %in% names(results)), nrow(results) > 0, length(colors) == 2)
  rates <- unlist(results[c("pct_ptx_not_used", "pct_ptx_used")], use.names = FALSE)
  finite_rates <- rates[is.finite(rates)]
  zoom_max <- if (length(finite_rates)) min(100, max(2, ceiling(max(finite_rates) * 1.45))) else 2
  panels <- nrow(results)
  width <- max(10, 3.6 * panels)
  p_label <- function(p) if (is.na(p)) "p not estimable" else
    if (p < 0.001) "p < 0.001" else sprintf("p = %.3f", p)
  draw <- function() {
    par(family = family, bg = "white")
    # Each technique has a full 0-100% panel with its own nested event inset.
    for (i in seq_len(panels)) {
      r <- results[i, ]
      left <- (i - 1) / panels
      right <- i / panels
      total <- c(r$n_not_used, r$n_used)
      events <- c(r$ptx_not_used, r$ptx_used)
      pct <- c(r$pct_ptx_not_used, r$pct_ptx_used)
      par(fig = c(left, right, 0.14, 0.86), new = i > 1,
          mar = c(4.3, 3.4, 3.2, 0.8), mgp = c(2, 0.55, 0), tcl = -0.22,
          las = 1, cex.axis = 0.85)
      plot(NA, xlim = c(0.45, 2.55), ylim = c(0, 100), xaxs = "i", yaxs = "i",
           axes = FALSE, xlab = "", ylab = if (i == 1) "Procedures (%)" else "")
      axis(2, at = seq(0, 100, 25))
      axis(1, at = 1:2, labels = paste0(c("Not used", "Used"), "\nN = ", total), tick = FALSE)
      for (j in 1:2) if (total[j] > 0) {
        rect(j - 0.28, 0, j + 0.28, 100, col = "#EDF0F3", border = NA)
        rect(j - 0.28, 0, j + 0.28, pct[j], col = colors[j], border = NA)
      }
      axis(1, at = c(0.45, 2.55), labels = FALSE, tick = FALSE)
      label <- if (r$technique == "Fluoroscopy without venogram") "Fluoroscopy\nwithout venogram" else
        if (r$technique == "Venogram or fluoroscopy") "Venogram / fluoroscopy" else r$technique
      title(main = label, cex.main = 1.05, line = 1.45)
      mtext(paste0("Pearson ", p_label(r$p_value), if (isTRUE(r$sparse_expected_counts)) " *" else ""),
            side = 3, line = 0.15, cex = 0.81)
      mtext(paste0("Unknown excluded: ", r$n_missing), side = 1, line = 3, cex = 0.7, col = "#59616B")
      par(fig = c(left + 0.21 / panels, right - 0.035 / panels, 0.37, 0.69),
          mar = c(1.9, 2.8, 1.2, 0.35), new = TRUE, mgp = c(1.7, 0.45, 0), tcl = -0.18)
      plot(NA, xlim = c(0.45, 2.55), ylim = c(0, zoom_max), xaxs = "i", yaxs = "i",
           axes = FALSE, xlab = "", ylab = "")
      # Opaque inset backgrounds keep full-height outer bars from showing through.
      rect(0.45, 0, 2.55, zoom_max, col = "white", border = NA)
      ticks <- pretty(c(0, zoom_max), n = 3)
      axis(2, at = ticks[ticks >= 0 & ticks <= zoom_max], cex.axis = 0.75)
      axis(1, at = 1:2, labels = c("Not used", "Used"), tick = FALSE, cex.axis = 0.7)
      for (j in 1:2) {
        if (total[j] > 0) rect(j - 0.24, 0, j + 0.24, pct[j], col = colors[j], border = NA)
        text(j, if (total[j] > 0) pct[j] + zoom_max * 0.07 else zoom_max * 0.07,
             labels = if (total[j] > 0) sprintf("%d/%d\n%.2f%%", events[j], total[j], pct[j]) else "N = 0\nNot estimable",
             cex = 0.68, adj = c(0.5, 0))
      }
      box(col = "#B8BEC5")
      mtext("PTX (%) - zoom", side = 3, line = 0.25, cex = 0.72)
    }
    par(fig = c(0, 1, 0, 1), mar = rep(0, 4), new = TRUE)
    plot.new()
    text(0.5, 0.96, cohort_label, cex = 1.22, font = 2)
    text(0.5, 0.065, "Inset labels: PTX events / procedures and PTX percentage. Techniques may overlap; counts are procedures, not unique patients.", cex = 0.78)
    text(0.5, 0.025, "Unadjusted Pearson chi-squared tests, no continuity correction. * Expected cell count <5; interpret cautiously.", cex = 0.75, col = "#59616B")
  }
  render <- function(path, type) {
    if (type == "pdf") pdf(path, width = width, height = 6, family = family, useDingbats = FALSE)
    else png(path, width = width, height = 6, units = "in", res = 300)
    on.exit(dev.off())
    draw()
  }
  render(paste0(output_stem, ".pdf"), "pdf")
  render(paste0(output_stem, ".png"), "png")
  invisible(results)
}
