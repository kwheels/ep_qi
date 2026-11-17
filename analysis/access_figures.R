# ggplot2 nested PTX figures from aggregate comparison tables. R 4.5.1+.
# JAMA-inspired colors: ggsci default palette, first two entries.
write_access_figure <- function(results, output_stem, cohort_label,
                                colors = getOption("hrs.figure_colors", c("#374E55", "#DF8F44")),
                                family = getOption("hrs.figure_family", "sans")) {
  if (!requireNamespace("ggplot2", quietly = TRUE) || packageVersion("ggplot2") < "3.4.0")
    stop("Install ggplot2 >= 3.4.0 to create abstract figures.")
  required <- c("technique", "n_used", "n_not_used", "ptx_used", "ptx_not_used",
                "pct_ptx_used", "pct_ptx_not_used", "p_value", "sparse_expected_counts")
  stopifnot(all(required %in% names(results)), nrow(results) > 0, length(colors) == 2)
  # Assemble grobs on an explicit disposable device, avoiding Rplots.pdf when
  # called from an otherwise non-graphical Rscript session.
  grDevices::pdf(NULL, width = 5, height = 5)
  assembly_device <- grDevices::dev.cur()
  on.exit(grDevices::dev.off(assembly_device), add = TRUE)
  rates <- unlist(results[c("pct_ptx_not_used", "pct_ptx_used")], use.names = FALSE)
  rates <- rates[is.finite(rates)]
  zoom_max <- if (length(rates)) min(100, max(2, ceiling(max(rates) * 1.45))) else 2
  p_label <- function(p) if (is.na(p)) "p not estimable" else
    if (p < 0.001) "p < 0.001" else sprintf("p = %.3f", p)
  clean_theme <- ggplot2::theme_classic(base_size = 8, base_family = family) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(),
      panel.background = ggplot2::element_rect(fill = "white", colour = NA),
      plot.background = ggplot2::element_rect(fill = "white", colour = NA),
      axis.line = ggplot2::element_line(colour = "black", linewidth = 0.55, lineend = "square"),
      axis.ticks = ggplot2::element_line(colour = "black", linewidth = 0.55),
      axis.ticks.length = grid::unit(2.5, "pt"),
      axis.text = ggplot2::element_text(colour = "black", face = "bold", size = 7),
      axis.text.x = ggplot2::element_text(margin = ggplot2::margin(t = 2.5)),
      axis.title.y = ggplot2::element_text(face = "bold", size = 7, margin = ggplot2::margin(r = 3)),
      plot.title = ggplot2::element_text(face = "bold", size = 9, hjust = 0.5, margin = ggplot2::margin(b = 3)),
      plot.subtitle = ggplot2::element_text(size = 8, hjust = 0.5, margin = ggplot2::margin(b = 2)),
      plot.margin = ggplot2::margin(3, 3, 2, 3), legend.position = "none")
  panels <- lapply(seq_len(nrow(results)), function(i) {
    r <- results[i, ]
    d <- data.frame(x = c(1.15, 1.85), group = factor(c("Not used", "Used"), levels = c("Not used", "Used")),
      total = c(r$n_not_used, r$n_used), events = c(r$ptx_not_used, r$ptx_used),
      rate = c(r$pct_ptx_not_used, r$pct_ptx_used))
    d$label <- ifelse(d$total > 0, sprintf("%d/%d\n%.2f%%", d$events, d$total, d$rate), "N = 0\nNot estimable")
    d$label_y <- ifelse(is.finite(d$rate), pmin(d$rate + zoom_max * 0.06, zoom_max * 0.83), zoom_max * 0.06)
    base <- ggplot2::ggplot(d, ggplot2::aes(x = x, y = rate, fill = group)) +
      ggplot2::geom_col(width = 0.54, colour = NA, na.rm = TRUE) +
      ggplot2::scale_fill_manual(values = colors, drop = FALSE) +
      clean_theme
    inset <- base +
      ggplot2::scale_x_continuous(limits = c(0.45, 2.55), breaks = d$x, labels = d$group, expand = c(0, 0)) +
      ggplot2::geom_text(ggplot2::aes(y = label_y, label = label), vjust = 0, size = 2.35,
                         lineheight = 0.95, colour = "black", family = family) +
      ggplot2::scale_y_continuous(limits = c(0, zoom_max), expand = c(0, 0)) +
      ggplot2::labs(x = NULL, y = NULL) +
      ggplot2::theme(plot.margin = ggplot2::margin(2, 2, 2, 2))
    label <- if (r$technique == "Fluoroscopy without venogram") "Fluoroscopy only" else
      if (r$technique == "Venogram or fluoroscopy") "Venogram / fluoroscopy" else r$technique
    main <- base +
      ggplot2::scale_x_continuous(limits = c(0.45, 2.55), breaks = d$x,
        labels = paste0(d$group, "\nN = ", d$total), expand = c(0, 0)) +
      ggplot2::scale_y_continuous(limits = c(0, 100), breaks = c(0, 50, 100), expand = c(0, 0)) +
      ggplot2::labs(x = NULL, y = "Pneumothorax Rate (%)", title = label) +
      ggplot2::annotation_custom(ggplot2::ggplotGrob(inset), xmin = 0.60, xmax = 2.55, ymin = 9, ymax = 93) +
      ggplot2::annotate("text", x = 1.5, y = 99, vjust = 1, size = 2.8, family = family,
        label = paste0(p_label(r$p_value), if (isTRUE(r$sparse_expected_counts)) " *" else ""))
    main
  })
  # Compose ggplot grobs using standard grid viewports, with no base plotting.
  rows <- ceiling(length(panels) / 2)
  layout <- grid::grid.layout(rows + 2, 2,
    heights = grid::unit(c(0.25, rep(4.35 / rows, rows), 0.40), "null"))
  children <- list(grid::textGrob(cohort_label, gp = grid::gpar(fontfamily = family, fontsize = 8, fontface = "bold"),
    vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1:2)))
  for (i in seq_along(panels)) {
    g <- ggplot2::ggplotGrob(panels[[i]])
    g$name <- paste0("technique-panel-", i)
    g$vp <- grid::viewport(layout.pos.row = 2 + (i - 1) %/% 2, layout.pos.col = 1 + (i - 1) %% 2)
    children[[length(children) + 1]] <- g
  }
  if (length(panels) == 3) children[[length(children) + 1]] <- grid::textGrob(
    "Full axis: 0-100%\nInsets: PTX / total; percent\nN = procedures\nTechniques may overlap",
    gp = grid::gpar(fontfamily = family, fontsize = 8),
    vp = grid::viewport(layout.pos.row = 3, layout.pos.col = 2))
  assumed_n <- if ("n_fluoroscopy_assumed" %in% names(results)) max(results$n_fluoroscopy_assumed, 0, na.rm = TRUE) else 0
  children[[length(children) + 1]] <- grid::textGrob(
    paste0("Labels: PTX events / procedures; PTX %. Groups overlap.\nPearson chi-squared; no continuity correction. * Expected count <5.\nFluoroscopy only = without venogram.",
           if (assumed_n > 0) paste0("\nFluoroscopy includes ", assumed_n, " scoped assumptions.") else ""),
    gp = grid::gpar(fontfamily = family, fontsize = 5.8),
    vp = grid::viewport(layout.pos.row = rows + 2, layout.pos.col = 1:2))
  figure <- grid::grobTree(children = do.call(grid::gList, children), vp = grid::viewport(layout = layout))
  ggplot2::ggsave(paste0(output_stem, ".pdf"), plot = figure, width = 5, height = 5, units = "in", bg = "white", useDingbats = FALSE)
  ggplot2::ggsave(paste0(output_stem, ".png"), plot = figure, width = 5, height = 5, units = "in", dpi = 300, bg = "white")
  invisible(panels)
}
