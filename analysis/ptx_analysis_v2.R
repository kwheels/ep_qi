#------------------------------------------------------
# Packages
#------------------------------------------------------
library(data.table)
library(R.utils)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(janitor)
library(readxl)
library(readr)
library(tidyverse)

# Run from the repository root: Rscript analysis/ptx_analysis_v2.R
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
analysis_dir <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]))) else
  if (file.exists("analysis/note_merge_helpers.R")) "analysis" else "."
source(file.path(analysis_dir, "note_merge_helpers.R"))
data_dir <- "/home/kwheels/cied_complications"
eligibility_file <- file.path(data_dir, "procedure_categories_v1", "procedure_eligibility.csv")
output_dir <- file.path(data_dir, "analysis_note_enriched")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)


#------------------------------------------------------
# 1. Read and standardize CIED procedure datasets
#------------------------------------------------------

# Main MiHeart procedure dataset
cied_main <- read_excel(
  "/home/kwheels/cied_complications/Micropuncture.xlsx"
) %>%
  clean_names() %>%
  mutate(
    mrn = str_trim(as.character(mrn)),
    patient_key = as.character(patient_key),
    pouch = as.character(pouch),
    procedure_source = "MiHeart database"
  )


# Manually abstracted procedures missing from MiHeart
manual_procedures <- read_excel(
  "/home/kwheels/cied_complications/manual_procedure_review.xlsx"
) %>%
  clean_names() %>%
  mutate(
    mrn = str_trim(as.character(mrn)),
    patient_key = as.character(patient_key),

    # Pouch was used, but the specific type is unknown
    pouch = "Unknown",

    procedure_source = "Manual chart review"
  )


#------------------------------------------------------
# 2. Combine and clean CIED procedure data
#------------------------------------------------------
# The original MiHeart database remains unchanged.
# Manual procedures are added only to the analysis dataset.

reviewed_notes <- read_reviewed_notes(data_dir, eligibility_file)
note_merge <- merge_note_documentation(bind_rows(cied_main, manual_procedures), reviewed_notes)
cied_all <- note_merge$data %>% mutate(pouch = factor(pouch), procedure_source = factor(procedure_source))
# Full baseline cohort stays here; note-only records are audited, not appended.
write_csv(note_merge$source_audit, file.path(output_dir, "database_source_access_audit.csv"))
write_csv(note_merge$note_only, file.path(output_dir, "notes_without_database_match.csv"))
write_csv(cied_all, file.path(output_dir, "procedure_access_crosscheck.csv"))
write_csv(cied_all %>% filter(database_row_count > 1), file.path(output_dir, "database_duplicate_procedures.csv"))
write_csv(cied_all %>% filter(invalid_database_key), file.path(output_dir, "invalid_database_keys.csv"))


#------------------------------------------------------
# 3. Read and clean manually reviewed PTX dataset
#------------------------------------------------------
ptx_review <- read_csv(
  "/home/kwheels/cied_complications/ptx_patients_clean.csv",
  show_col_types = FALSE
) %>%
  clean_names() %>%
  mutate(
    # Use the same MRN matching key as the enriched cohort.
    mrn = normalize_mrn(mrn),

    # Convert "74 Years" -> 74
    age = as.integer(parse_number(age)),

    # Categorical variables
    ethnicity = factor(ethnicity),
    race = factor(race),
    sex = factor(sex),
    procedural_complication = factor(procedural_complication),
    procedure_type = factor(procedure_type),
    laterality = factor(laterality),
    management = factor(management),
    outcome = factor(outcome),
    status = factor(status),

    # Dates
    birth_date = mdy(birth_date),
    date_diagnosed = mdy(date_diagnosed),

    # PTX must be diagnosed within 14 days after the procedure
    earliest_procedure_date = date_diagnosed - days(14)
  ) %>%
  select(
    -name
  )


#------------------------------------------------------
# 4. Identify all eligible PTX-procedure matches
#------------------------------------------------------
# A PTX is eligible to match a procedure if:
#   1. MRN matches
#   2. Procedure occurred on or before PTX diagnosis
#   3. PTX was diagnosed within 14 days of the procedure

ptx_matches <- cied_all %>%
  inner_join(
    ptx_review,
    by = join_by(
      mrn,
      procedure_date >= earliest_procedure_date,
      procedure_date <= date_diagnosed
    ),
    na_matches = "never"
  ) %>%
  mutate(
    days_procedure_to_ptx = as.integer(
      date_diagnosed - procedure_date
    )
  ) %>%
  group_by(
    mrn,
    date_diagnosed
  ) %>%
  mutate(
    n_eligible_procedures = n(),
    multiple_eligible_procedures = n() > 1
  ) %>%
  ungroup()


#------------------------------------------------------
# 5. Assign each PTX to a single CIED procedure
#------------------------------------------------------
# If more than one procedure falls within the 14-day window,
# attribute the PTX to the most recent preceding procedure.

ptx_assigned <- ptx_matches %>%
  group_by(
    mrn,
    date_diagnosed
  ) %>%
  slice_min(
    order_by = days_procedure_to_ptx,
    n = 1,
    with_ties = FALSE
  ) %>%
  ungroup()


#------------------------------------------------------
# 6. Retain PTX variables needed for final merge
#------------------------------------------------------
ptx_for_merge <- ptx_assigned %>%
  select(
    mrn,
    procedure_date,
    birth_date,
    age,
    ethnicity,
    race,
    sex,
    procedural_complication,
    procedure_type,
    date_diagnosed,
    laterality,
    peak_size_mm,
    management,
    outcome,
    status,
    comments,
    days_procedure_to_ptx,
    n_eligible_procedures,
    multiple_eligible_procedures
  )


#------------------------------------------------------
# 7. Merge PTX outcomes onto complete procedure cohort
#------------------------------------------------------
# Every CIED procedure remains in the dataset.
# PTX information is attached only to the procedure to which
# the complication was ultimately assigned.

cied_analysis <- cied_all %>%
  left_join(
    ptx_for_merge,
    by = c(
      "mrn",
      "procedure_date"
    )
  ) %>%
  mutate(
    # Binary outcome for subsequent analyses
    pneumothorax = if_else(
      !is.na(date_diagnosed),
      1L,
      0L
    )
  )


#------------------------------------------------------
# 8. Quality-control checks
#------------------------------------------------------

# PTX cases for which more than one procedure was initially eligible
ptx_match_check <- ptx_matches %>%
  filter(
    multiple_eligible_procedures
  ) %>%
  arrange(
    mrn,
    date_diagnosed,
    days_procedure_to_ptx
  )

ptx_match_check


# PTX cases that could not be matched to a qualifying procedure
# This should contain the clinically uncertain case that is excluded.
ptx_unmatched <- ptx_review %>%
  anti_join(
    ptx_matches %>%
      distinct(
        mrn,
        date_diagnosed
      ),
    by = c(
      "mrn",
      "date_diagnosed"
    )
  )

ptx_unmatched


#------------------------------------------------------
# 9. Final dataset checks
#------------------------------------------------------

# Total number of procedures
nrow(cied_analysis)

# Procedures by data source
table(cied_analysis$procedure_source)

# Number of manually abstracted procedures
sum(
  cied_analysis$procedure_source == "Manual chart review",
  na.rm = TRUE
)

# Number of included PTX events
sum(
  cied_analysis$pneumothorax,
  na.rm = TRUE
)

# PTX outcome distribution
table(cied_analysis$pneumothorax)

# Number of unmatched PTX records
nrow(ptx_unmatched)

# Dataset structure
glimpse(cied_analysis)

##################################################
################ Analysis ########################
##################################################


#------------------------------------------------------
# Define procedures with potential transvenous lead access
#------------------------------------------------------
# Include procedures containing:
#   - New Implant
#   - Lead Revision
#   - Lead Reposition
#   - Upgrade/Downgrade
#   - Lead Extraction
#
# Lead Extraction is included because procedure_list may not
# capture all components of a case. Manual review identified
# an extraction-coded PTX case in which a new device was also
# implanted.
#
# The original criteria below are now the fallback when notes are absent or
# unresolved. Reviewed note exclusions and database generator-only exclusions
# are applied in apply_access_eligibility(); the full baseline is retained.

eligibility_audit <- apply_access_eligibility(cied_analysis)
cied_analysis_access <- eligibility_audit %>% filter(access_cohort_include)
write_csv(eligibility_audit, file.path(output_dir, "access_cohort_eligibility_audit.csv"))
write_csv(eligibility_audit %>% filter(!access_cohort_include), file.path(output_dir, "excluded_access_procedures.csv"))
write_csv(eligibility_audit %>% filter(is.na(note_access_eligible) & has_procedure_note),
          file.path(output_dir, "unresolved_note_eligibility.csv"))
note_enrichment_summary <- eligibility_audit %>% summarise(
  n_baseline_procedures = n(), n_with_notes = sum(has_procedure_note),
  n_without_notes = sum(!has_procedure_note), n_access_cohort = sum(access_cohort_include),
  n_original_database_access_criteria = sum(database_access_eligible & !database_generator_only),
  n_original_database_source_rows = sum(database_row_count),
  n_note_exclusions = sum(access_eligibility_basis == "excluded_note_nonqualifying"),
  n_generator_only_exclusions = sum(database_generator_only),
  n_unresolved_note_eligibility = sum(has_procedure_note & is.na(note_access_eligible)),
  n_us_added = sum(us_added_from_note), n_venogram_added = sum(venogram_added_from_note),
  n_micropuncture_added = sum(micro_puncture_added_from_note), n_fluoroscopy_added = sum(fluoroscopy_added_from_note)
)
print(note_enrichment_summary)
write_csv(note_enrichment_summary, file.path(output_dir, "note_enrichment_summary.csv"))

#------------------------------------------------------
# Check resulting access cohort
#------------------------------------------------------

# Cohort size and PTX count
cied_analysis_access %>%
  summarise(
    n_procedures = n(),
    n_ptx = sum(pneumothorax),
    pct_ptx = 100 * mean(pneumothorax)
  )


# Qualifying procedure components
cied_analysis_access %>%
  summarise(
    new_implant = sum(new_implant),
    lead_revision = sum(lead_revision),
    lead_reposition = sum(lead_reposition),
    upgrade_downgrade = sum(upgrade_downgrade)
  )


# Specifically examine the PTX cases
cied_analysis_access %>%
  filter(
    pneumothorax == 1
  ) %>%
  count(
    procedure_list,
    sort = TRUE
  )


#------------------------------------------------------
# Identify PTX excluded by access-procedure criteria
#------------------------------------------------------

ptx_excluded_access <- cied_analysis %>%
  filter(
    pneumothorax == 1
  ) %>%
  anti_join(
    cied_analysis_access %>%
      select(
        mrn,
        procedure_date
      ),
    by = c(
      "mrn",
      "procedure_date"
    )
  )

# Review relevant procedure and PTX information
ptx_excluded_access %>%
  select(
    mrn,
    procedure_date,
    procedure_list,
    us,
    venogram,
    micro_puncture,
    date_diagnosed,
    days_procedure_to_ptx,
    comments
  )

#------------------------------------------------------
# PTX vs no-PTX: procedural access techniques
#------------------------------------------------------

# Convert access variables to logical values
# while preserving missing data as NA
cied_analysis_access <- cied_analysis_access %>%
  mutate(
    us_yes = as.character(us) == "TRUE",
    venogram_yes = as.character(venogram) == "TRUE",
    micropuncture_yes = as.character(micro_puncture) == "TRUE",
    fluoroscopy_yes = as.character(fluoroscopy) == "TRUE"
  )

write_csv(cied_analysis_access, file.path(output_dir, "cied_analysis_access_enriched.csv"))


#------------------------------------------------------
# Function to summarize each access technique
#------------------------------------------------------
compare_access <- function(data, variable, label) {

  # Restrict each comparison to procedures with known
  # values for the access variable
  dat <- data %>%
    filter(!is.na(.data[[variable]]))

  # Counts and percentages by PTX status
  summary <- dat %>%
    group_by(pneumothorax) %>%
    summarise(
      n_total = n(),
      n_yes = sum(.data[[variable]]),
      pct_yes = 100 * n_yes / n_total,
      .groups = "drop"
    )

  # Fisher's exact test
  test_table <- table(
    dat$pneumothorax,
    dat[[variable]]
  )

  p_value <- fisher.test(test_table)$p.value

  # Return one row for easy comparison
  tibble(
    Technique = label,

    No_PTX = sprintf(
      "%d/%d (%.1f%%)",
      summary$n_yes[summary$pneumothorax == 0],
      summary$n_total[summary$pneumothorax == 0],
      summary$pct_yes[summary$pneumothorax == 0]
    ),

    PTX = sprintf(
      "%d/%d (%.1f%%)",
      summary$n_yes[summary$pneumothorax == 1],
      summary$n_total[summary$pneumothorax == 1],
      summary$pct_yes[summary$pneumothorax == 1]
    ),

    p_value = p_value
  )
}


#------------------------------------------------------
# Run comparisons
#------------------------------------------------------
access_comparison <- bind_rows(
  compare_access(
    cied_analysis_access,
    "us_yes",
    "Ultrasound"
  ),

  compare_access(
    cied_analysis_access,
    "venogram_yes",
    "Venogram"
  ),

  compare_access(
    cied_analysis_access,
    "micropuncture_yes",
    "Micropuncture"
  ),
  compare_access(
    cied_analysis_access,
    "fluoroscopy_yes",
    "Fluoroscopy without venogram"
  )
) %>%
  mutate(
    p_value = signif(p_value, 3)
  )


#------------------------------------------------------
# Results
#------------------------------------------------------
access_comparison

#------------------------------------------------------
# Transpose PTX vs access technique table
#------------------------------------------------------

access_comparison_transposed <- access_comparison %>%
  select(
    Technique,
    No_PTX,
    PTX
  ) %>%
  pivot_longer(
    cols = c(No_PTX, PTX),
    names_to = "PTX_Status",
    values_to = "Value"
  ) %>%
  pivot_wider(
    names_from = Technique,
    values_from = Value
  ) %>%
  mutate(
    PTX_Status = recode(
      PTX_Status,
      No_PTX = "No PTX",
      PTX = "PTX"
    )
  )

access_comparison_transposed

#------------------------------------------------------
# PTX frequency among procedures using each technique
#------------------------------------------------------

ptx_by_technique <- bind_rows(

  cied_analysis_access %>%
    filter(us_yes) %>%
    summarise(
      Technique = "Ultrasound",
      n_procedures = n(),
      n_ptx = sum(pneumothorax),
      pct_ptx = 100 * mean(pneumothorax)
    ),

  cied_analysis_access %>%
    filter(venogram_yes) %>%
    summarise(
      Technique = "Venogram",
      n_procedures = n(),
      n_ptx = sum(pneumothorax),
      pct_ptx = 100 * mean(pneumothorax)
    ),

  cied_analysis_access %>%
    filter(micropuncture_yes) %>%
    summarise(
      Technique = "Micropuncture",
      n_procedures = n(),
      n_ptx = sum(pneumothorax),
      pct_ptx = 100 * mean(pneumothorax)
    )
) %>%
  mutate(
    `PTX, N (%)` = sprintf(
      "%d/%d (%.2f%%)",
      n_ptx,
      n_procedures,
      pct_ptx
    )
  )

ptx_by_technique

#------------------------------------------------------
# Ultrasound and venogram use
# N (% of all procedures)
#------------------------------------------------------

us_venogram_table <- table(
  Ultrasound = ifelse(
    cied_analysis_access$us == TRUE,
    "Ultrasound",
    "No Ultrasound"
  ),
  Venogram = ifelse(
    cied_analysis_access$venogram == TRUE,
    "Venogram",
    "No Venogram"
  )
)

# Add totals
us_venogram_table <- addmargins(us_venogram_table)

# Format as N (% of all procedures)
n_total <- nrow(cied_analysis_access)

us_venogram_formatted <- as.data.frame.matrix(
  matrix(
    sprintf(
      "%d (%.1f%%)",
      us_venogram_table,
      100 * us_venogram_table / n_total
    ),
    nrow = nrow(us_venogram_table),
    dimnames = dimnames(us_venogram_table)
  )
)

us_venogram_formatted



#------------------------------------------------------
# Procedure volume, PTX rate, and technique use by year
#------------------------------------------------------

year_summary <- cied_analysis_access %>%
  mutate(
    procedure_year = year(procedure_date)
  ) %>%
  filter(
    procedure_year >= 2019,
    procedure_year <= 2026
  ) %>%
  group_by(
    procedure_year
  ) %>%
  summarise(
    # Total procedures
    n_procedures = n(),

    # Pneumothorax
    n_ptx = sum(pneumothorax, na.rm = TRUE),
    pct_ptx = 100 * mean(pneumothorax, na.rm = TRUE),

    # Ultrasound
    n_us = sum(us_yes, na.rm = TRUE),
    pct_us = 100 * mean(us_yes, na.rm = TRUE),

    # Venogram
    n_venogram = sum(venogram_yes, na.rm = TRUE),
    pct_venogram = 100 * mean(venogram_yes, na.rm = TRUE),

    # Micropuncture
    n_micropuncture = sum(micropuncture_yes, na.rm = TRUE),
    pct_micropuncture = 100 * mean(micropuncture_yes, na.rm = TRUE),

    .groups = "drop"
  )


#------------------------------------------------------
# Display year-level summary
#------------------------------------------------------

year_summary %>%
  mutate(
    across(
      starts_with("pct_"),
      ~ round(.x, 2)
    )
  )


#------------------------------------------------------
# PTX by access technique: 2x2 tables + Fisher tests
#------------------------------------------------------

# Helper function
analyze_technique <- function(data, technique_var, technique_label) {

  # Keep complete observations for this technique
  df <- data %>%
    filter(
      !is.na(.data[[technique_var]]),
      !is.na(pneumothorax)
    )

  # Raw 2x2 table
  tab <- table(
    Technique = df[[technique_var]],
    PTX = df$pneumothorax
  )

  # Fisher exact test
  fisher_result <- fisher.test(tab)

  # Summary table
  summary <- df %>%
    group_by(
      Used = .data[[technique_var]]
    ) %>%
    summarise(
      n_procedures = n(),
      n_ptx = sum(pneumothorax),
      pct_ptx = 100 * mean(pneumothorax),
      .groups = "drop"
    ) %>%
    mutate(
      Technique = technique_label,
      Exposure = if_else(Used, "Used", "Not used"),
      `PTX, N (%)` = sprintf(
        "%d/%d (%.2f%%)",
        n_ptx,
        n_procedures,
        pct_ptx
      ),
      p_value = fisher_result$p.value
    ) %>%
    select(
      Technique,
      Exposure,
      n_procedures,
      n_ptx,
      pct_ptx,
      `PTX, N (%)`,
      p_value
    )

  list(
    summary = summary,
    table = tab,
    fisher = fisher_result
  )
}


#------------------------------------------------------
# Run for each technique
#------------------------------------------------------

us_result <- analyze_technique(
  cied_analysis_access,
  "us_yes",
  "Ultrasound"
)

venogram_result <- analyze_technique(
  cied_analysis_access,
  "venogram_yes",
  "Venogram"
)

micropuncture_result <- analyze_technique(
  cied_analysis_access,
  "micropuncture_yes",
  "Micropuncture"
)


#------------------------------------------------------
# Combined summary table
#------------------------------------------------------

technique_ptx_summary <- bind_rows(
  us_result$summary,
  venogram_result$summary,
  micropuncture_result$summary
) %>%
  mutate(
    p_value = if_else(
      p_value < 0.001,
      "<0.001",
      sprintf("%.3f", p_value)
    )
  )

technique_ptx_summary

#------------------------------------------------------
# Raw 2x2 tables
#------------------------------------------------------

us_result$table
venogram_result$table
micropuncture_result$table

#------------------------------------------------------
# PTX by access strategy
# Categories may overlap with micropuncture
#------------------------------------------------------

access_strategy_summary <- bind_rows(

  # Ultrasound without venogram
  cied_analysis_access %>%
    filter(us_yes & !venogram_yes) %>%
    summarise(
      Access = "Ultrasound only",
      n_procedures = n(),
      n_ptx = sum(pneumothorax, na.rm = TRUE),
      pct_ptx = 100 * mean(pneumothorax, na.rm = TRUE)
    ),

  # Venogram without ultrasound
  cied_analysis_access %>%
    filter(!us_yes & venogram_yes) %>%
    summarise(
      Access = "Venogram only",
      n_procedures = n(),
      n_ptx = sum(pneumothorax, na.rm = TRUE),
      pct_ptx = 100 * mean(pneumothorax, na.rm = TRUE)
    ),

  # Both ultrasound and venogram
  cied_analysis_access %>%
    filter(us_yes & venogram_yes) %>%
    summarise(
      Access = "Ultrasound + venogram",
      n_procedures = n(),
      n_ptx = sum(pneumothorax, na.rm = TRUE),
      pct_ptx = 100 * mean(pneumothorax, na.rm = TRUE)
    ),

  # Neither US or venogram
  cied_analysis_access %>%
    filter(!us_yes & !venogram_yes) %>%
    summarise(
      Access = "Neither ultrasound nor venogram",
      n_procedures = n(),
      n_ptx = sum(pneumothorax, na.rm = TRUE),
      pct_ptx = 100 * mean(pneumothorax, na.rm = TRUE)
    ),

) %>%
  mutate(
    `PTX, N (%)` = sprintf(
      "%d/%d (%.2f%%)",
      n_ptx,
      n_procedures,
      pct_ptx
    )
  )

access_strategy_summary

#------------------------------------------------------
# Micropuncture use by ultrasound/venogram strategy
#------------------------------------------------------

micro_by_access <- cied_analysis_access %>%
  mutate(
    access_strategy = case_when(
      us_yes & !venogram_yes  ~ "Ultrasound only",
      !us_yes & venogram_yes  ~ "Venogram only",
      us_yes & venogram_yes   ~ "Ultrasound + venogram",
      !us_yes & !venogram_yes ~ "Neither ultrasound nor venogram",
      TRUE ~ NA_character_
    ),
    micropuncture = if_else(
      micropuncture_yes,
      "Micropuncture",
      "No micropuncture"
    )
  ) %>%
  filter(
    !is.na(access_strategy),
    !is.na(micropuncture)
  ) %>%
  count(
    access_strategy,
    micropuncture
  ) %>%
  group_by(access_strategy) %>%
  mutate(
    pct = 100 * n / sum(n),
    value = sprintf("%d (%.1f%%)", n, pct)
  ) %>%
  ungroup() %>%
  select(
    access_strategy,
    micropuncture,
    value
  ) %>%
  pivot_wider(
    names_from = micropuncture,
    values_from = value
  )

micro_by_access


#------------------------------------------------------
# Ultrasound vs venogram use for new implants
# N (% of new implant procedures)
#------------------------------------------------------

new_implant_access <- cied_analysis_access %>%
  filter(new_implant)

new_implant_us_venogram <- table(
  Ultrasound = ifelse(
    new_implant_access$us_yes,
    "Ultrasound",
    "No ultrasound"
  ),
  Venogram = ifelse(
    new_implant_access$venogram_yes,
    "Venogram",
    "No venogram"
  )
)

# Add row/column totals
new_implant_us_venogram <- addmargins(new_implant_us_venogram)

# Format as N (% of all new implant procedures)
n_new_implants <- nrow(new_implant_access)

new_implant_us_venogram_formatted <- as.data.frame.matrix(
  matrix(
    sprintf(
      "%d (%.1f%%)",
      new_implant_us_venogram,
      100 * new_implant_us_venogram / n_new_implants
    ),
    nrow = nrow(new_implant_us_venogram),
    dimnames = dimnames(new_implant_us_venogram)
  )
)

new_implant_us_venogram_formatted


#------------------------------------------------------
# Fisher exact tests for access strategy and PTX
#------------------------------------------------------

# Create 5 binary exposure variables
cied_analysis_access <- cied_analysis_access %>%
  mutate(
    us_only = us_yes & !venogram_yes,
    venogram_only = !us_yes & venogram_yes,
    us_venogram = us_yes & venogram_yes,
    neither_us_venogram = !us_yes & !venogram_yes
  )


# Function to run 2x2 Fisher exact test
run_fisher <- function(data, exposure_var, exposure_label) {

  df <- data %>%
    filter(
      !is.na(.data[[exposure_var]]),
      !is.na(pneumothorax)
    )

  # 2x2 table
  tab <- table(
    Exposure = df[[exposure_var]],
    PTX = df$pneumothorax
  )

  fisher_result <- fisher.test(tab)

  # Counts and PTX rates for exposed vs unexposed
  summary <- df %>%
    group_by(Exposure = .data[[exposure_var]]) %>%
    summarise(
      n_procedures = n(),
      n_ptx = sum(pneumothorax),
      pct_ptx = 100 * mean(pneumothorax),
      .groups = "drop"
    ) %>%
    mutate(
      Technique = exposure_label,
      Exposure = if_else(Exposure, "Yes", "No"),
      `PTX, N (%)` = sprintf(
        "%d/%d (%.2f%%)",
        n_ptx,
        n_procedures,
        pct_ptx
      ),
      odds_ratio = unname(fisher_result$estimate),
      ci_low = fisher_result$conf.int[1],
      ci_high = fisher_result$conf.int[2],
      p_value = fisher_result$p.value
    )

  list(
    summary = summary,
    table = tab,
    fisher = fisher_result
  )
}


#------------------------------------------------------
# Run all 5 comparisons
#------------------------------------------------------

fisher_results <- list(

  us_only = run_fisher(
    cied_analysis_access,
    "us_only",
    "Ultrasound only"
  ),

  venogram_only = run_fisher(
    cied_analysis_access,
    "venogram_only",
    "Venogram only"
  ),

  us_venogram = run_fisher(
    cied_analysis_access,
    "us_venogram",
    "Ultrasound + venogram"
  ),

  neither = run_fisher(
    cied_analysis_access,
    "neither_us_venogram",
    "Neither ultrasound nor venogram"
  ),

  micropuncture = run_fisher(
    cied_analysis_access,
    "micropuncture_yes",
    "Micropuncture"
  )
)

#------------------------------------------------------
# Final results table
#------------------------------------------------------

fisher_summary <- map_dfr(
  fisher_results,
  ~ .x$summary %>%
    select(
      Technique,
      Exposure,
      `PTX, N (%)`,
      odds_ratio,
      ci_low,
      ci_high,
      p_value
    ) %>%
    pivot_wider(
      names_from = Exposure,
      values_from = `PTX, N (%)`,
      names_prefix = "Exposure_"
    ) %>%
    mutate(
      `Odds ratio (95% CI)` = sprintf(
        "%.2f (%.2f–%.2f)",
        odds_ratio,
        ci_low,
        ci_high
      ),
      `P-value` = if_else(
        p_value < 0.001,
        "<0.001",
        sprintf("%.3f", p_value)
      )
    ) %>%
    select(
      Technique,
      `Exposed` = Exposure_Yes,
      `Not exposed` = Exposure_No,
      `P-value`
    )
)

fisher_summary


#------------------------------------------------------
# Firth regression
#------------------------------------------------------

library(logistf)

firth_model <- logistf(
  pneumothorax ~ us_yes + venogram_yes + micropuncture_yes,
  data = cied_analysis_access
)

summary(firth_model)

firth_results <- tibble(
  Predictor = c(
    "Ultrasound",
    "Venogram",
    "Micropuncture"
  ),
  OR = exp(firth_model$coefficients[-1]),
  CI_low = exp(firth_model$ci.lower[-1]),
  CI_high = exp(firth_model$ci.upper[-1]),
  p_value = firth_model$prob[-1]
) %>%
  mutate(
    `OR (95% CI)` = sprintf(
      "%.2f (%.2f–%.2f)",
      OR,
      CI_low,
      CI_high
    ),
    `P-value` = if_else(
      p_value < 0.001,
      "<0.001",
      sprintf("%.3f", p_value)
    )
  ) %>%
  select(
    Predictor,
    `OR (95% CI)`,
    `P-value`
  )

firth_results

#------------------------------------------------------
# Create small PTX/access dataset for co-author
# One row per procedure
#------------------------------------------------------

ptx_access_export <- cied_analysis_access %>%
  transmute(
    procedure_id = row_number(),
    pneumothorax = as.integer(pneumothorax),
    venogram = as.integer(venogram_yes),
    ultrasound = as.integer(us_yes),
    micropuncture = as.integer(micropuncture_yes)
  )

# Check
glimpse(ptx_access_export)
colSums(ptx_access_export)

# Export
write_csv(
  ptx_access_export,
  file.path(output_dir, "ptx_access_light.csv")
)
