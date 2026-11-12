# R 4.5.1-compatible helpers. Source note_merge_helpers.R first.

abstract_cohort <- function(data, revision_policy = c("access_flag", "exclude")) {
  revision_policy <- match.arg(revision_policy)
  data <- apply_access_eligibility(data)
  text <- coalesce(as.character(data$procedure_list), "")
  nontransvenous <- str_detect(text, regex("loop[ -]*recorder|\\bILR\\b|leadless|epicardial|sub[ -]?(q|cutaneous)[ -]*(ICD|defibrillator)|\\bSQ?[ -]?ICD\\b|extra[ -]*vascular[ -]*(ICD|defibrillator)|\\bEV[ -]*ICD\\b", TRUE))
  data$unconfirmed_revision_access <- (data$lead_revision | data$lead_reposition) &
    !data$new_implant & !(data$note_access_eligible %in% TRUE) & !(data$note_access_eligible %in% FALSE)
  evidence_columns <- intersect(c("us", "venogram", "micro_puncture", "fluoroscopy", "fluoroscopy_documented",
    "us_database", "venogram_database", "micro_puncture_database", "fluoroscopy_database",
    "us_note", "venogram_note", "micro_puncture_note", "fluoroscopy_note",
    "cephalic_cutdown", "cephalic_cutdown_database", "cephalic_cutdown_note"), names(data))
  positive <- lapply(data[evidence_columns], function(x) as_access_flag(x) %in% TRUE)
  data$has_positive_access_flag <- if (length(positive)) Reduce(`|`, positive) else rep(FALSE, nrow(data))
  data$access_cohort_include[nontransvenous & !(data$note_access_eligible %in% TRUE)] <- FALSE
  data$access_eligibility_basis[nontransvenous & !(data$note_access_eligible %in% TRUE)] <- "excluded_nontransvenous_database_type"
  affected <- data$unconfirmed_revision_access & !nontransvenous & !data$database_generator_only
  retain_revision <- affected & data$has_positive_access_flag & revision_policy == "access_flag"
  data$access_cohort_include[affected] <- retain_revision[affected]
  data$access_eligibility_basis[retain_revision] <- "included_revision_positive_access_flag"
  data$access_eligibility_basis[affected & !retain_revision] <- if (revision_policy == "exclude")
    "excluded_unconfirmed_revision_access" else "excluded_revision_no_positive_access_flag"
  data$procedure_group <- case_when(
    data$new_implant & (data$lead_revision | data$lead_reposition | data$upgrade_downgrade) ~ "New implant plus revision/upgrade",
    data$new_implant ~ "New implant",
    data$lead_revision | data$lead_reposition | data$upgrade_downgrade ~ "Revision/reposition/upgrade",
    data$lead_extraction ~ "Extraction-coded case with implant/access eligibility",
    TRUE ~ "Other/unspecified"
  )
  data
}

attach_ptx <- function(database, ptx) {
  # One reviewed event per MRN/diagnosis date; never use PTX-only demographics.
  ptx <- ptx %>% transmute(mrn = normalize_mrn(mrn), date_diagnosed = parse_procedure_date(date_diagnosed)) %>% distinct()
  ptx$event_id <- seq_len(nrow(ptx))
  ptx$earliest_procedure_date <- ptx$date_diagnosed - 14
  keys <- database %>% select(.key, mrn, procedure_date)
  matches <- inner_join(keys, ptx, by = join_by(mrn, procedure_date >= earliest_procedure_date,
                                              procedure_date <= date_diagnosed), na_matches = "never") %>%
    mutate(days_to_ptx = as.integer(date_diagnosed - procedure_date))
  assigned <- matches %>% group_by(event_id) %>% slice_min(days_to_ptx, n = 1, with_ties = FALSE) %>% ungroup()
  outcomes <- assigned %>% group_by(.key) %>% summarise(ptx_event_count = n(), .groups = "drop")
  result <- left_join(database, outcomes, by = ".key") %>%
    mutate(ptx_event_count = coalesce(ptx_event_count, 0L), pneumothorax = as.integer(ptx_event_count > 0))
  stopifnot(nrow(result) == nrow(database))
  list(data = result, assigned = assigned, unmatched = anti_join(ptx, assigned, by = "event_id"),
       multiple_candidates = matches %>% add_count(event_id) %>% filter(n > 1))
}

three_way_or <- function(a, b) {
  # These are different techniques: FALSE venogram cannot establish absence of
  # fluoroscopy when fluoroscopy is unknown. R's logical OR preserves that NA.
  as_access_flag(a) | as_access_flag(b)
}

access_chisquare <- function(data, variable, label) {
  known <- !is.na(data[[variable]]) & !is.na(data$pneumothorax)
  exposure <- data[[variable]][known]
  outcome <- data$pneumothorax[known]
  tab <- table(factor(exposure, levels = c(FALSE, TRUE)), factor(outcome, levels = c(0, 1)))
  estimable <- all(rowSums(tab) > 0) && all(colSums(tab) > 0)
  expected <- if (sum(tab)) outer(rowSums(tab), colSums(tab)) / sum(tab) else matrix(NA_real_, 2, 2)
  p <- statistic <- NA_real_
  if (estimable) {
    test <- suppressWarnings(chisq.test(tab, correct = FALSE))
    p <- unname(test$p.value)
    statistic <- unname(test$statistic)
  }
  n_yes <- sum(exposure %in% TRUE)
  n_no <- sum(exposure %in% FALSE)
  tibble(technique = label, n_known = sum(known), n_missing = sum(!known),
         n_used = n_yes, ptx_used = sum(tab[2, 2]), pct_ptx_used = if (n_yes) 100 * tab[2, 2] / n_yes else NA_real_,
         n_not_used = n_no, ptx_not_used = sum(tab[1, 2]), pct_ptx_not_used = if (n_no) 100 * tab[1, 2] / n_no else NA_real_,
         pearson_chisq = statistic, df = if (estimable) 1L else NA_integer_, p_value = p,
         min_expected = if (sum(tab)) min(expected) else NA_real_,
         n_expected_below_5 = if (sum(tab)) sum(expected < 5) else NA_integer_,
         sparse_expected_counts = if (sum(tab)) any(expected < 5) else NA,
         test_status = if (estimable) "Pearson chi-squared; no continuity correction" else "Not estimable: absent exposure or outcome group")
}

access_comparison_table <- function(data, split_imaging = FALSE) {
  if (split_imaging) {
    data$venogram_for_comparison <- as_access_flag(data$venogram)
    raw_fluoro <- if ("fluoroscopy_documented" %in% names(data)) data$fluoroscopy_documented else data$fluoroscopy
    data$fluoroscopy_for_comparison <- fluoroscopy_without_venogram(as_access_flag(raw_fluoro), data$venogram_for_comparison)
    imaging <- bind_rows(
      access_chisquare(data, "venogram_for_comparison", "Venogram"),
      access_chisquare(data, "fluoroscopy_for_comparison", "Fluoroscopy without venogram"))
  } else {
    imaging <- access_chisquare(data, "venogram_or_fluoroscopy", "Venogram or fluoroscopy")
  }
  bind_rows(
    access_chisquare(data, "micropuncture", "Micropuncture"),
    access_chisquare(data, "ultrasound", "Ultrasound"),
    imaging) %>%
    mutate(pct_used_among_known = if_else(n_known > 0, 100 * n_used / n_known, NA_real_),
           pct_used_among_all_procedures = if (nrow(data)) 100 * n_used / nrow(data) else NA_real_)
}

access_sensitivity_cohorts <- function(data) {
  valid_mrn <- !is.na(data$mrn) & nzchar(trimws(as.character(data$mrn)))
  list(full = data,
       completedemo = data[valid_mrn & data$demographics_matched %in% TRUE, , drop = FALSE],
       noteonly = data[data$has_procedure_note %in% TRUE, , drop = FALSE])
}

sensitivity_cohort_counts <- function(cohorts) {
  bind_rows(lapply(names(cohorts), function(name) {
    x <- cohorts[[name]]
    tibble(analysis = name, n_procedures = nrow(x),
           n_identifiable_patients = n_distinct(x$mrn[!is.na(x$mrn) & nzchar(x$mrn)]),
           n_procedures_with_ptx = sum(x$pneumothorax),
           pct_procedures_with_ptx = if (nrow(x)) 100 * mean(x$pneumothorax) else NA_real_,
           n_with_notes = sum(x$has_procedure_note %in% TRUE),
           n_with_demographic_link = sum(x$demographics_matched %in% TRUE))
  }))
}

note_access_coverage <- function(data) {
  data <- data[as_access_flag(data$has_procedure_note) %in% TRUE, , drop = FALSE]
  data$ultrasound <- as_access_flag(if ("ultrasound" %in% names(data)) data$ultrasound else data$us)
  data$venogram <- as_access_flag(data$venogram)
  raw <- if ("fluoroscopy_documented" %in% names(data)) data$fluoroscopy_documented else data$fluoroscopy
  data$fluoroscopy_without_venogram <- fluoroscopy_without_venogram(as_access_flag(raw), data$venogram)
  data$cephalic_cutdown <- if ("cephalic_cutdown" %in% names(data)) as_access_flag(data$cephalic_cutdown) else rep(NA, nrow(data))
  flags <- cbind(data$ultrasound, data$venogram, data$fluoroscopy_without_venogram)
  n_positive <- rowSums(flags, na.rm = TRUE)
  n_unknown <- rowSums(is.na(flags))
  data$guidance_review_reason <- ifelse(n_positive > 0, "Positive guidance documented",
    ifelse(n_unknown > 0, "No positive guidance flag; at least one unknown", "Ultrasound, venogram and fluoroscopy all FALSE"))
  data$micropuncture <- as_access_flag(if ("micropuncture" %in% names(data)) data$micropuncture else data$micro_puncture)
  data$pneumothorax <- as_access_flag(data$pneumothorax)
  review <- data[n_positive == 0, , drop = FALSE] %>% select(any_of(c(
    "mrn", "procedure_date", "guidance_review_reason", "pneumothorax", "procedure_list", "procedure_group",
    "note_qualifying_procedures", "note_procedures", "access_eligibility_basis", "note_access_eligible",
    "micropuncture", "ultrasound", "venogram", "fluoroscopy_without_venogram", "fluoroscopy_documented",
    "cephalic_cutdown", "cephalic_cutdown_database", "cephalic_cutdown_note",
    "us_database", "us_note", "venogram_database", "venogram_note", "fluoroscopy_database", "fluoroscopy_note",
    "micro_puncture_database", "micro_puncture_note", "database_rows", "note_access_rows", "note_category_needs_review")))
  summary <- tibble(
    n_note_procedures = nrow(data), n_any_guidance_positive = sum(n_positive > 0),
    n_no_guidance_positive = sum(n_positive == 0),
    n_no_guidance_all_false = sum(n_positive == 0 & n_unknown == 0),
    n_no_guidance_with_unknown = sum(n_positive == 0 & n_unknown > 0),
    n_multiple_guidance_positive = sum(n_positive > 1), sum_individual_positive_counts = sum(n_positive),
    n_no_guidance_but_micropuncture = sum(n_positive == 0 & data$micropuncture %in% TRUE),
    n_cephalic_cutdown_positive = sum(data$cephalic_cutdown %in% TRUE),
    n_no_guidance_but_cephalic_cutdown = sum(n_positive == 0 & data$cephalic_cutdown %in% TRUE),
    n_any_guidance_or_cutdown_positive = sum(n_positive > 0 | data$cephalic_cutdown %in% TRUE),
    n_no_guidance_or_cutdown_positive = sum(n_positive == 0 & !(data$cephalic_cutdown %in% TRUE)),
    n_ptx_no_guidance_positive = sum(n_positive == 0 & data$pneumothorax %in% TRUE))
  patterns <- data %>% group_by(ultrasound, venogram, fluoroscopy_without_venogram, cephalic_cutdown) %>%
    summarise(n_procedures = n(), n_ptx = sum(pneumothorax %in% TRUE), .groups = "drop")
  list(review = review %>% filter(!(cephalic_cutdown %in% TRUE)), guidance_review = review,
       summary = summary, patterns = patterns)
}

schema_without_values <- function(data, dataset) {
  bind_rows(lapply(names(data), function(column) {
    x <- data[[column]]
    missing <- is.na(x) | trimws(as.character(x)) == ""
    tibble(dataset = dataset, variable = column, storage_class = paste(class(x), collapse = "/"),
           rows_profiled = length(x), n_missing = sum(missing), n_distinct_nonmissing = n_distinct(x[!missing]))
  }))
}

dob_format_profile <- function(x) {
  text <- trimws(as.character(x))
  format <- case_when(
    is.na(text) | text == "" ~ "missing",
    grepl("^[+-]?[0-9]+(\\.[0-9]+)?$", text) ~ "numeric_text_possible_excel_serial",
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", text) ~ "ISO_date_or_timestamp",
    grepl("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}", text) ~ "slash_date",
    TRUE ~ "other_date_text"
  )
  tibble(format = format, character_length = nchar(text)) %>% count(format, character_length, name = "n_rows")
}

parse_dob <- function(x, encoding = c("auto", "excel")) {
  encoding <- match.arg(encoding)
  text <- trimws(as.character(x))
  numeric <- !is.na(text) & grepl("^[+-]?[0-9]+(\\.[0-9]+)?$", text)
  # Do not let a generic date parser interpret serial numbers as calendar text.
  result <- as.Date(rep(NA_character_, length(text)))
  # DOB is a calendar date. Parse its date portion explicitly so timestamp
  # precision cannot change format detection or accidentally reverse date order.
  iso <- !is.na(text) & grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}([ T]|$)", text)
  slash <- !is.na(text) & grepl("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}([ T]|$)", text)
  result[iso] <- as.Date(substr(text[iso], 1, 10), format = "%Y-%m-%d")
  result[slash] <- as.Date(sub("[ T].*$", "", text[slash]), format = "%m/%d/%Y")
  if (encoding == "excel") result[numeric] <- as.Date(floor(as.numeric(text[numeric])), origin = "1899-12-30")
  result
}

refresh_field_map <- function(existing, suggested) {
  # Fill only previously unresolved automatic mappings, never user selections.
  if (!"status" %in% names(existing)) return(existing)
  for (i in seq_len(nrow(existing))) {
    blank <- is.na(existing$column[i]) || !nzchar(trimws(existing$column[i]))
    automatic <- !is.na(existing$status[i]) && grepl("^not identified|^ambiguous", existing$status[i])
    replacement <- suggested %>% filter(variable == existing$variable[i], !is.na(column), column != "")
    if (blank && automatic && nrow(replacement) == 1) {
      existing$source_file[i] <- replacement$source_file
      existing$column[i] <- replacement$column
      existing$status[i] <- "newly recognized unique candidate; verify"
    }
  }
  existing
}

field_candidates <- function(demographic_dir) {
  files <- c(file.path(demographic_dir, "patients.csv"), list.files(file.path(demographic_dir, "long"), "\\.csv$", full.names = TRUE))
  fields <- list(dob = c("dob", "birthdate", "dateofbirth"), sex = c("sex", "gender", "sexname", "gendername", "sexdescription", "genderdescription"),
                 race = c("race", "racedescription", "racename"),
                 ethnicity = c("ethnicity", "ethnicityname", "ethnicitydescription", "ethnicgroup", "ethnicgroupname", "ethnicgroupdescription"),
                 medical_history = c("problemdescription"))
  bind_rows(lapply(files[file.exists(files)], function(path) {
    names_in_file <- names(readr::read_csv(path, n_max = 0, col_types = readr::cols(.default = "c"), show_col_types = FALSE))
    short <- tolower(gsub("[^a-zA-Z0-9]", "", sub(".*__", "", names_in_file)))
    relative <- if (basename(path) == "patients.csv") "patients.csv" else paste0("long/", basename(path))
    bind_rows(lapply(names(fields), function(field) {
      matches <- names_in_file[short %in% fields[[field]]]
      if (field == "medical_history") matches <- matches[grepl("ClarityMedicalHistory__", matches, fixed = TRUE)]
      tibble(variable = field, source_file = relative, column = matches)
    }))
  }))
}

suggest_field_map <- function(candidates) {
  bind_rows(lapply(c("dob", "sex", "race", "ethnicity", "medical_history"), function(field) {
    options <- candidates %>% filter(variable == field)
    preferred <- options %>% filter(source_file == "patients.csv")
    if (nrow(preferred)) options <- preferred
    if (nrow(options) == 1) mutate(options, status = "unique candidate; verify") else
      tibble(variable = field, source_file = "", column = "", status = if (nrow(options)) "ambiguous: select from field_candidates.csv" else "not identified")
  }))
}

load_demographic_fields <- function(root, map, dob_encoding = "auto") {
  master <- readr::read_csv(file.path(root, "patients.csv"), col_types = readr::cols(.default = "c"), show_col_types = FALSE)
  if (!"MRN" %in% names(master)) stop("patients.csv must contain MRN.")
  ids <- tibble(mrn = normalize_mrn(master$MRN)) %>% filter(!is.na(mrn)) %>% distinct()
  issues <- list()
  for (field in c("dob", "sex", "race", "ethnicity", "medical_history")) {
    selection <- map %>% filter(variable == field, !is.na(source_file), source_file != "", !is.na(column), column != "")
    if (nrow(selection) > 1) stop("Field map has more than one selection for ", field)
    if (!nrow(selection)) { ids[[field]] <- NA_character_; next }
    path <- normalizePath(file.path(root, selection$source_file), mustWork = TRUE)
    allowed_root <- paste0(normalizePath(root, winslash = "/"), "/")
    if (!startsWith(normalizePath(path, winslash = "/"), allowed_root)) stop("Field map must reference files inside demographic output folder.")
    raw <- readr::read_csv(path, col_types = readr::cols(.default = "c"), show_col_types = FALSE)
    if (!all(c("MRN", selection$column) %in% names(raw))) stop("Field-map column missing for ", field)
    values <- tibble(mrn = normalize_mrn(raw$MRN), value = trimws(as.character(raw[[selection$column]]))) %>%
      mutate(value = na_if(value, "")) %>% filter(!is.na(mrn))
    grouped <- values %>% group_by(mrn) %>% summarise(
      n_values = n_distinct(value, na.rm = TRUE),
      value = if (field %in% c("race", "ethnicity", "medical_history")) {
        result <- paste(unique(na.omit(value)), collapse = " | "); if (nzchar(result)) result else NA_character_
      } else { known <- unique(na.omit(value)); if (length(known) == 1) known else NA_character_ }, .groups = "drop")
    issues[[field]] <- grouped %>% filter(n_values > 1) %>% mutate(variable = field)
    grouped <- grouped %>% select(mrn, value)
    names(grouped)[2] <- field
    ids <- left_join(ids, grouped, by = "mrn")
  }
  dob_profile <- dob_format_profile(ids$dob)
  dob_raw <- ids$dob
  ids$dob <- parse_dob(ids$dob, dob_encoding)
  dob_qc <- tibble(mrn = ids$mrn, dob_original = dob_raw, dob_parsed = ids$dob) %>%
    filter(!is.na(dob_original), dob_original != "", is.na(dob_parsed))
  list(data = ids, issues = bind_rows(issues), dob_profile = dob_profile, dob_qc = dob_qc)
}

add_demographics <- function(cohort, demographics) {
  stopifnot(!anyDuplicated(demographics$mrn))
  collisions <- intersect(setdiff(names(demographics), "mrn"), names(cohort))
  if (length(collisions)) names(cohort)[match(collisions, names(cohort))] <- paste0("baseline_", collisions)
  result <- left_join(cohort, mutate(demographics, demographics_matched = TRUE), by = "mrn", na_matches = "never")
  stopifnot(nrow(result) == nrow(cohort))
  result <- result %>% mutate(demographics_matched = coalesce(demographics_matched, FALSE),
    age_at_procedure = floor(as.numeric(lubridate::time_length(lubridate::interval(dob, procedure_date), "years"))),
    age_invalid = !is.na(age_at_procedure) & (age_at_procedure < 0 | age_at_procedure > 120),
    age_at_procedure = if_else(age_invalid, NA_real_, age_at_procedure))
  result
}

export_reviewed_diagnoses <- function(input, output, min_patients = 5L) {
  data <- readr::read_csv(input, col_types = readr::cols(.default = "c"), show_col_types = FALSE)
  required <- c("reviewed_term", "approved_for_sharing", "n_patients", "n_procedures", "proposed_group")
  if (!all(required %in% names(data))) stop("Unexpected diagnosis review columns.")
  approved <- tolower(trimws(data$approved_for_sharing)) %in% c("true", "yes", "1")
  result <- data %>% mutate(n_patients = as.integer(n_patients), n_procedures = as.integer(n_procedures)) %>%
    filter(approved, !is.na(reviewed_term), nzchar(trimws(reviewed_term)), n_patients >= min_patients) %>%
    select(reviewed_term, n_patients, n_procedures, proposed_group)
  readr::write_csv(result, output)
  invisible(result)
}

demographic_summary <- function(data, unit) {
  sex <- tolower(trimws(data$sex))
  female <- sex %in% c("female", "f")
  recognized <- sex %in% c("female", "f", "male", "m", "other", "nonbinary", "non-binary", "intersex")
  ages <- data$age_at_procedure[!is.na(data$age_at_procedure)]
  tibble(unit = unit, n = nrow(data), n_demographics_matched = sum(data$demographics_matched),
         n_age_known = length(ages), n_age_missing = sum(is.na(data$age_at_procedure)),
         mean_age = if (length(ages)) mean(ages) else NA_real_, sd_age = if (length(ages) > 1) sd(ages) else NA_real_,
         n_female = sum(female), n_sex_recognized = sum(recognized), n_sex_missing_or_unmapped = sum(!recognized),
         pct_female_known = if (sum(recognized)) 100 * sum(female) / sum(recognized) else NA_real_)
}

diagnosis_inventory <- function(patients, cohort) {
  source <- patients %>% filter(!is.na(medical_history), nzchar(medical_history)) %>%
    select(mrn, medical_history) %>% tidyr::separate_rows(medical_history, sep = "\\|") %>%
    mutate(diagnosis_term = trimws(medical_history)) %>% filter(nzchar(diagnosis_term)) %>% distinct(mrn, diagnosis_term)
  counts <- cohort %>% filter(!is.na(mrn)) %>% count(mrn, name = "n_procedures")
  source %>% left_join(counts, by = "mrn") %>% group_by(diagnosis_term) %>%
    summarise(n_patients = n(), n_procedures = sum(n_procedures), .groups = "drop") %>%
    arrange(desc(n_patients), diagnosis_term) %>% mutate(reviewed_term = "", approved_for_sharing = "", proposed_group = "")
}
