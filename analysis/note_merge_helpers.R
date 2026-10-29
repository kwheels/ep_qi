# Preliminary note/database reconciliation. Does not modify source datasets.

normalize_mrn <- function(x) {
  value <- trimws(as.character(x))
  value <- sub("\\.0+$", "", value)
  valid <- !is.na(value) & grepl("^[0-9]+$", value)
  value[!valid] <- NA_character_
  value[valid] <- sub("^0+(?=[0-9])", "", value[valid], perl = TRUE)
  value
}

as_access_flag <- function(x, blank_zero = FALSE) {
  value <- tolower(trimws(as.character(x)))
  missing <- is.na(value) | value %in% c("", "na", "null", "n/a")
  yes <- value %in% c("1", "1.0", "true", "t", "yes", "y")
  no <- value %in% c("0", "0.0", "false", "f", "no", "n")
  if (any(!missing & !yes & !no)) stop("Unrecognized access label; expected 0/1 or TRUE/FALSE.")
  result <- rep(NA, length(value))
  result[yes] <- TRUE
  result[no] <- FALSE
  if (blank_zero) result[missing] <- FALSE
  result
}

anything_counts <- function(x) {
  if (any(x %in% TRUE)) return(TRUE)
  if (any(x %in% FALSE)) return(FALSE)
  NA
}

combine_access <- function(database, notes) {
  # TRUE wins; FALSE is retained when documented; both unknown stays unknown.
  ifelse(database %in% TRUE | notes %in% TRUE, TRUE,
         ifelse(database %in% FALSE | notes %in% FALSE, FALSE, NA))
}

fluoroscopy_without_venogram <- function(fluoroscopy, venogram) {
  # Analysis category, not a claim that fluoroscopy was physically absent.
  ifelse(venogram %in% TRUE, FALSE,
         ifelse(venogram %in% FALSE, fluoroscopy, NA))
}

eligibility_consensus <- function(x) {
  known <- unique(x[!is.na(x)])
  if (length(known) == 1L) known[[1]] else NA
}

parse_procedure_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  value <- trimws(as.character(x))
  suppressWarnings(as.Date(lubridate::parse_date_time(
    value, orders = c("ymd HMS", "ymd HM", "ymd", "mdy HMS", "mdy"), quiet = TRUE
  )))
}

read_reviewed_notes <- function(folder, eligibility_file) {
  access_file <- file.path(folder, "access_technique_reviewed.csv")
  if (!file.exists(access_file) || !file.exists(eligibility_file)) {
    stop("Missing reviewed access CSV or procedure_eligibility.csv; verify configured paths.")
  }
  access <- readr::read_csv(access_file, col_types = readr::cols(.default = "c"),
                           na = c("", "NA"), show_col_types = FALSE) %>% janitor::clean_names()
  required <- c("phi_mrn", "proc_date", "ultrasound_used", "venogram_used", "micropuncture_used", "fluoroscopy_used")
  if (!all(required %in% names(access))) stop("Reviewed access CSV has unexpected columns.")
  access <- access %>% mutate(
    mrn = normalize_mrn(phi_mrn), procedure_date = parse_procedure_date(proc_date),
    us_note = as_access_flag(ultrasound_used, TRUE),
    venogram_note = as_access_flag(venogram_used, TRUE),
    micro_puncture_note = as_access_flag(micropuncture_used, TRUE),
    fluoroscopy_note = as_access_flag(fluoroscopy_used, TRUE)
  )
  if (any(is.na(access$mrn) | is.na(access$procedure_date))) stop("Reviewed access CSV contains invalid procedure keys.")
  access <- access %>% group_by(mrn, procedure_date) %>% summarise(
    note_access_rows = n(),
    across(c(us_note, venogram_note, micro_puncture_note, fluoroscopy_note), anything_counts),
    .groups = "drop"
  )
  eligibility <- readr::read_csv(eligibility_file, col_types = readr::cols(.default = "c"),
                                show_col_types = FALSE) %>% janitor::clean_names()
  if (!all(c("mrn", "procedure_date", "note_access_eligible") %in% names(eligibility))) {
    stop("Procedure eligibility CSV has unexpected columns.")
  }
  eligibility <- eligibility %>% mutate(
    mrn = normalize_mrn(mrn), procedure_date = parse_procedure_date(procedure_date),
    note_access_eligible = as_access_flag(note_access_eligible)
  )
  if (any(is.na(eligibility$mrn) | is.na(eligibility$procedure_date))) stop("Eligibility CSV contains invalid procedure keys.")
  if (!"needs_review" %in% names(eligibility)) eligibility$needs_review <- "0"
  if (!"qualifying_procedures" %in% names(eligibility)) eligibility$qualifying_procedures <- NA_character_
  if (!"all_procedures" %in% names(eligibility)) eligibility$all_procedures <- NA_character_
  if (!"eligibility_status" %in% names(eligibility)) eligibility$eligibility_status <- NA_character_
  eligibility <- eligibility %>% group_by(mrn, procedure_date) %>% summarise(
    note_eligibility_rows = n(),
    note_eligibility_conflict = n_distinct(note_access_eligible, na.rm = TRUE) > 1L,
    note_access_eligible = eligibility_consensus(note_access_eligible),
    note_category_needs_review = any(as_access_flag(needs_review) %in% TRUE),
    note_qualifying_procedures = paste(unique(na.omit(qualifying_procedures)), collapse = " | "),
    note_procedures = paste(unique(na.omit(all_procedures)), collapse = " | "),
    note_eligibility_status = paste(unique(na.omit(eligibility_status)), collapse = " | "),
    .groups = "drop"
  )
  full_join(access, eligibility, by = c("mrn", "procedure_date"), na_matches = "never")
}

merge_note_documentation <- function(database, notes) {
  required <- c("mrn", "procedure_date", "procedure_list", "us", "venogram", "micro_puncture", "procedure_source")
  if (!all(required %in% names(database))) stop("Database schema is missing required fields.")
  database <- database %>% select(-any_of(c("last_name", "lastname", "firstname", "first_name", "patient_key")))
  # Do not invent a fluoroscopy variable from US/venogram absence.
  fluoro_names <- intersect(c("fluoroscopy", "fluoro", "fluoroscopy_used", "fluoro_used"), names(database))
  database$fluoroscopy <- if (length(fluoro_names)) {
    Reduce(combine_access, lapply(database[fluoro_names], as_access_flag))
  } else rep(NA, nrow(database))
  database <- database %>% mutate(
    database_row = row_number(), mrn_original = as.character(mrn), mrn = normalize_mrn(mrn),
    procedure_date = parse_procedure_date(procedure_date),
    across(c(us, venogram, micro_puncture), as_access_flag),
    .key = if_else(is.na(mrn) | is.na(procedure_date), paste0("invalid_row_", database_row),
                   paste(mrn, procedure_date, sep = "__"))
  )
  source_audit <- database %>% select(database_row, mrn_original, mrn, procedure_date, procedure_source,
                                      procedure_list, us, venogram, micro_puncture, fluoroscopy, .key)
  # Collapse database duplicates at procedure level; preserve every original row in audit.
  single_value <- function(x) {
    known <- unique(x[!is.na(x)])
    if (length(known) == 1L) known[[1]] else NA_character_
  }
  extra <- setdiff(names(database), c(".key", "mrn", "procedure_date", "database_row", "mrn_original",
                                     "procedure_list", "procedure_source", "us", "venogram", "micro_puncture", "fluoroscopy"))
  database <- database %>% group_by(.key) %>% summarise(
    mrn = first(mrn), procedure_date = first(procedure_date), database_row_count = n(),
    database_rows = paste(database_row, collapse = "; "),
    mrn_original_values = paste(unique(mrn_original), collapse = "; "),
    procedure_list = paste(unique(na.omit(procedure_list)), collapse = " | "),
    procedure_source = paste(unique(na.omit(procedure_source)), collapse = " + "),
    across(c(us, venogram, micro_puncture, fluoroscopy), anything_counts),
    across(all_of(extra), ~ single_value(as.character(.x))),
    .groups = "drop"
  )
  if (anyDuplicated(notes[c("mrn", "procedure_date")])) stop("Notes are not unique by procedure key.")
  note_only <- anti_join(notes, database, by = c("mrn", "procedure_date"), na_matches = "never")
  n_before <- nrow(database)
  combined <- left_join(database, notes, by = c("mrn", "procedure_date"), na_matches = "never")
  stopifnot(nrow(combined) == n_before)
  combined <- combined %>% mutate(
    has_procedure_note = !is.na(note_access_rows) | !is.na(note_eligibility_rows),
    invalid_database_key = is.na(mrn) | is.na(procedure_date),
    across(c(us, venogram, micro_puncture, fluoroscopy), identity, .names = "{.col}_database"),
    us = combine_access(us_database, us_note),
    venogram = combine_access(venogram_database, venogram_note),
    micro_puncture = combine_access(micro_puncture_database, micro_puncture_note),
    fluoroscopy = combine_access(fluoroscopy_database, fluoroscopy_note)
  )
  for (technique in c("us", "venogram", "micro_puncture", "fluoroscopy")) {
    db <- combined[[paste0(technique, "_database")]]
    note <- combined[[paste0(technique, "_note")]]
    combined[[paste0(technique, "_discrepancy")]] <- ifelse(!is.na(db) & !is.na(note), db != note, NA)
    combined[[paste0(technique, "_added_from_note")]] <- note %in% TRUE & !(db %in% TRUE)
  }
  combined <- combined %>% mutate(
    fluoroscopy_documented = fluoroscopy,
    fluoroscopy = fluoroscopy_without_venogram(fluoroscopy_documented, venogram),
    fluoroscopy_note_exclusive = fluoroscopy_without_venogram(fluoroscopy_note, venogram_note),
    imaging_access_group = case_when(
      venogram %in% TRUE ~ "Venogram",
      fluoroscopy %in% TRUE ~ "Fluoroscopy without venogram",
      venogram %in% FALSE & fluoroscopy %in% FALSE ~ "Neither",
      TRUE ~ "Unknown"
    )
  )
  list(data = combined, source_audit = source_audit, note_only = note_only)
}

apply_access_eligibility <- function(data) {
  # Keep all rows in this audit table; filter only when constructing the access cohort.
  types <- coalesce(as.character(data$procedure_list), "")
  flag <- function(pattern) str_detect(types, regex(pattern, ignore_case = TRUE))
  data$new_implant <- flag("New Implant")
  data$lead_revision <- flag("Lead Revision")
  data$lead_reposition <- flag("Lead Reposition")
  data$upgrade_downgrade <- flag("Upgrade/Downgrade")
  data$lead_extraction <- flag("Lead Extraction")
  data$leadless <- flag("leadless")
  db_component <- data$new_implant | data$lead_revision | data$lead_reposition |
    data$upgrade_downgrade | data$lead_extraction
  data$database_access_eligible <- db_component & !data$leadless
  data$database_generator_only <- flag("generator.*(change|replacement|exchange)|(change|replacement|exchange).*generator") & !db_component
  data$access_cohort_include <- ifelse(data$note_access_eligible %in% TRUE, TRUE,
    ifelse(data$note_access_eligible %in% FALSE, FALSE, data$database_access_eligible)) & !data$database_generator_only
  data$access_eligibility_basis <- case_when(
    data$database_generator_only ~ "excluded_database_generator_only",
    data$note_access_eligible %in% FALSE ~ "excluded_note_nonqualifying",
    data$note_access_eligible %in% TRUE ~ "included_note_qualifying",
    data$database_access_eligible ~ "included_database_criteria_notes_absent_or_unresolved",
    TRUE ~ "excluded_database_criteria_notes_absent_or_unresolved"
  )
  data
}
