# Synthetic, hand-counted combination denominators and Pearson comparisons.
suppressPackageStartupMessages({library(dplyr); library(stringr)})
source("analysis/note_merge_helpers.R")
source("analysis/abstract_helpers.R")
x <- tibble(micropuncture = c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, NA),
  ultrasound = c(TRUE, TRUE, FALSE, NA, TRUE, FALSE, NA, TRUE),
  venogram_or_fluoroscopy = c(FALSE, TRUE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE),
  pneumothorax = c(1L, 0L, 1L, 0L, 0L, 1L, 0L, 0L),
  fluoroscopy_assumed = c(FALSE, TRUE, rep(FALSE, 6)))
result <- access_combination_table(x)
stopifnot(nrow(result) == 12)
pair <- filter(result, definition == "At least these techniques", technique == "Micropuncture + Ultrasound")
stopifnot(pair$n_used == 2, pair$ptx_used == 1, pair$n_not_used == 4, pair$ptx_not_used == 2,
          pair$n_missing == 2, pair$n_fluoroscopy_assumed_in_group == 1)
expected_p <- suppressWarnings(chisq.test(matrix(c(1, 1, 2, 2), nrow = 2, byrow = TRUE), correct = FALSE)$p.value)
stopifnot(isTRUE(all.equal(pair$p_value, expected_p)))
exact <- filter(result, definition == "Exact pattern", technique == "Micropuncture + Ultrasound")
stopifnot(exact$n_used == 1, exact$ptx_used == 1, exact$n_known == 5, exact$n_missing == 3)
stopifnot(all(filter(result, definition == "Exact pattern")$n_known == 5))
stopifnot(sum(filter(result, definition == "Exact pattern")$n_used) == 5)
stopifnot(isTRUE(all.equal(filter(result, definition == "Exact pattern")$p_value_bh,
                           p.adjust(filter(result, definition == "Exact pattern")$p_value, "BH"))))
x$venogram <- c(FALSE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE)
x$fluoroscopy_analysis <- c(FALSE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, FALSE)
split <- access_combination_table(x, split_imaging = TRUE)
stopifnot(nrow(split) == 19)
stopifnot(!any(grepl("Venogram \\+ Fluoroscopy", split$technique)))
fluoro_pair <- filter(split, definition == "At least these techniques", technique == "Micropuncture + Fluoroscopy without venogram")
stopifnot(fluoro_pair$n_used == 1, fluoro_pair$ptx_used == 1)
empty <- access_combination_table(x[FALSE, ])
stopifnot(all(empty$n_known == 0), all(is.na(empty$p_value)))
x$pneumothorax <- 0L
stopifnot(all(is.na(access_combination_table(x)$p_value)))
message("Synthetic access-combination checks passed.")
