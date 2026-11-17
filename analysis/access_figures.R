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
  width <- 5
  height <- 5
  rows <- ceiling(panels / 2)
  p_label <- function(p) if (is.na(p)) "p not estimable" else
    if (p < 0.001) "p < 0.001" else sprintf("p = %.3f", p)
  draw <- function() {
    par(family = family, bg = "white", col.axis = "black", col.lab = "black",
        fg = "black", font.axis = 2, lwd = 1.4)
    # Each technique has a full 0-100% panel with its own nested event inset.
    for (i in seq_len(panels)) {
      r <- results[i, ]
      left <- ((i - 1) %% 2) / 2
      right <- left + 0.5
      top <- 0.91 - ((i - 1) %/% 2) * 0.82 / rows
      bottom <- top - 0.82 / rows
      total <- c(r$n_not_used, r$n_used)
      events <- c(r$ptx_not_used, r$ptx_used)
      pct <- c(r$pct_ptx_not_used, r$pct_ptx_used)
      x <- c(1.15, 1.85)
      par(fig = c(left, right, bottom, top), new = i > 1,
          mai = c(0.34, 0.38, 0.31, 0.07), mgp = c(1.6, 0.38, 0), tcl = -0.24,
          las = 1, cex.axis = 0.8)
      plot(NA, xlim = c(0.45, 2.55), ylim = c(0, 100), xaxs = "i", yaxs = "i",
           axes = FALSE, xlab = "", ylab = "")
      axis(2, at = c(0, 50, 100))
      mtext("Pneumothorax Rate (%)", side = 2, line = 1.35, las = 0, cex = 0.72, font = 2)
      axis(1, at = x, labels = FALSE, pos = 0)
      segments(0.45, 0, 2.55, 0)
      mtext(paste0(c("Not used", "Used"), "\nN = ", total), side = 1, at = x,
            line = 0.8, cex = 0.8, font = 2)
      for (j in 1:2) if (total[j] > 0) {
        rect(x[j] - 0.27, 0, x[j] + 0.27, pct[j], col = colors[j], border = NA)
      }
      label <- if (r$technique == "Fluoroscopy without venogram") "Fluoroscopy only" else
        if (r$technique == "Venogram or fluoroscopy") "Venogram / fluoroscopy" else r$technique
      title(main = label, cex.main = 1, line = 1.55)
      mtext(paste0(p_label(r$p_value), if (isTRUE(r$sparse_expected_counts)) " *" else ""),
            side = 3, line = 0.2, cex = 0.8)
      par(fig = c(left + 0.105, right - 0.005, bottom + 0.105, top - 0.065),
          mai = c(0.18, 0.20, 0.13, 0.025), new = TRUE, mgp = c(1.4, 0.3, 0), tcl = -0.22)
      plot(NA, xlim = c(0.45, 2.55), ylim = c(0, zoom_max), xaxs = "i", yaxs = "i",
           axes = FALSE, xlab = "", ylab = "")
      # Keep the zoom panel background white.
      rect(0.45, 0, 2.55, zoom_max, col = "white", border = NA)
      ticks <- pretty(c(0, zoom_max), n = 3)
      axis(2, at = ticks[ticks >= 0 & ticks <= zoom_max], cex.axis = 0.75)
      axis(1, at = x, labels = FALSE, pos = 0)
      segments(0.45, 0, 2.55, 0)
      mtext(c("Not used", "Used"), side = 1, at = x, line = 0.65, cex = 0.7, font = 2)
      for (j in 1:2) {
        if (total[j] > 0) rect(x[j] - 0.27, 0, x[j] + 0.27, pct[j], col = colors[j], border = NA)
        text(x[j], if (total[j] > 0) pct[j] + zoom_max * 0.07 else zoom_max * 0.07,
             labels = if (total[j] > 0) sprintf("%d/%d\n%.2f%%", events[j], total[j], pct[j]) else "N = 0\nNot estimable",
             cex = 0.68, adj = c(0.5, 0))
      }

      mtext("Zoomed view", side = 3, line = 0.3, cex = 0.72)
    }
    par(fig = c(0, 1, 0, 1), mar = rep(0, 4), new = TRUE)
    plot.new()
    text(0.5, 0.985, cohort_label, cex = 0.85, font = 2)
    if (panels == 3) {
      text(0.76, 0.38, "Full axis: 0-100%\nInset: PTX (%)\nLabels: PTX / total; percent\nN = procedures\nTechniques may overlap",
           cex = 0.85, adj = 0.5)
    }
    text(0.5, 0.065, "Full axis: 0-100%. Inset: PTX events / procedures; PTX %. Groups overlap.", cex = 0.7)
    text(0.5, 0.03, "Pearson chi-squared; no correction. * Expected count <5. Fluoroscopy only = no venogram.", cex = 0.65)

  }
  render <- function(path, type) {
    if (type == "pdf") pdf(path, width = width, height = height, pointsize = 9, family = family, useDingbats = FALSE)
    else png(path, width = width, height = height, units = "in", res = 300, pointsize = 9)
    on.exit(dev.off())
    draw()
  }
  render(paste0(output_stem, ".pdf"), "pdf")
  render(paste0(output_stem, ".png"), "png")
  invisible(results)
}
