# Demographic workbook extraction

Run on Armis2 from the `ep_qi` repository root. Python 3.6+ and `openpyxl` are required. No R dependency and no network operations in the extractor.

```bash
git pull
python3 -m pip install --user -r requirements.txt
python3 demographic_extraction/extract_demographics.py \
  /home/kwheels/cied_complications/YOUR_WORKBOOK.xlsx \
  --out-dir /home/kwheels/cied_complications/demographic_extraction_output
```

Replace `YOUR_WORKBOOK.xlsx` with the real filename. The output directory may already exist; named generated files are replaced. Other files are preserved. If a tab is renamed, removed or reclassified on a later run, an old long CSV may remain; `sheet_summary.csv` identifies only the current run's output files. Do not consume a partial run if the script exits with an error.

## Patient-level file

`patients.csv` contains one row per normalized **PatientID in PatientInfo**, with `MRN` first and `PatientID` second. It starts with every mapped patient, even if other tabs contain no records. All other PatientInfo fields (including DOB) are retained with a `PatientInfo__` prefix. DOB date cells become ISO dates such as `1950-01-02`.

For every other tab except ClarityMedicalHistory, the script checks actual nonblank PatientIDs:

- No repeated IDs: merge its columns into `patients.csv`, prefixed `TabName__ColumnName` to prevent collisions.
- Any repeated ID: preserve **the entire tab** as a long CSV under `long/`, named for the tab. MRN and PatientID are first, followed by the Excel source-row number and original columns. Original date/time cells use ISO text. A tab with mostly single records but one repeated PatientID is classified as repeated measures.
- No PatientID column: retain the tab under `long/` with blank identifiers and audit its rows. No positional join is attempted.

The first worksheet row must be the header row; extra title rows must be removed before extraction. Blank rows and trailing empty columns are ignored. Duplicate/ambiguous headers or populated cells with no header stop the run. Sheets with no data still appear in the classification summary. All worksheets, including hidden ones, are considered. Formulas are read from Excel's saved cached values; the script does not calculate formulas.

## Medical history

`ClarityMedicalHistory` always receives special handling, regardless of its number of rows per patient. For each mapped patient, nonblank `ProblemDescription` values are trimmed, exact duplicates removed, and descriptions joined in first-seen order with ` | `. The single resulting field in `patients.csv` is:

```text
ClarityMedicalHistory__ProblemDescription
```

Other medical-history columns are not merged; no diagnosis parsing is performed. Unmatched history rows, including their complete original fields, remain in the unmatched audit. A literal pipe already in a description is preserved, so the combined text is intended for later text searching rather than lossless splitting on every pipe.

## Identifiers and QC

PatientIDs are joined case-insensitively after trimming surrounding whitespace; hyphens and internal characters are preserved. Original PatientID spelling from PatientInfo is used in the master output. Long files retain the PatientID shown in the source tab.

Text MRNs are preserved exactly, including leading zeros. General-format cells that visibly contain leading zeros should be stored as text. Actual numeric MRNs trigger `numeric_mrn_verify_leading_zeros`; zero padding is not guessed. If a fixed MRN length is confirmed, use `--mrn-width N` to pad digit MRNs to that width. Non-digit/null MRNs stay blank and are audited.

PatientInfo QC includes:

- Repeated PatientIDs, even when duplicates are identical.
- One PatientID associated with conflicting nonblank MRNs: keep one PatientID row but leave its MRN blank. Each original mapping is retained in QC.
- Conflicting other PatientInfo fields (such as DOB): leave that field blank and retain the originals in QC. A single known value plus blanks retains the known value.
- Multiple PatientIDs linked to the same MRN: keep separate PatientID rows and flag them for adjudication before joining by MRN. MRNs differing only by leading-zero padding are considered the same for this QC check.
- Missing PatientIDs, missing/invalid MRNs, and numeric-MRN formatting uncertainty.

PatientIDs not in PatientInfo do not create new master patients. Their singleton/history rows are preserved in `unmatched_rows.csv` as original-field JSON; their repeated-measure rows also remain in the relevant long CSV with blank MRN. Rows with missing PatientID are retained in those audits too. Conflicting mapped IDs have blank MRNs in extracts; their mapping issues are recorded in QC rather than labeled as absent PatientIDs.

## Outputs

- `patients.csv`: merged patient-level data and collapsed medical history.
- `long/TabName.csv`: repeated measures or tabs without PatientID.
- `sheet_summary.csv`: classification, row counts, unique/repeated ID counts and current output location for every tab.
- `qc_issues.csv`: issue type, original sheet/row, PatientID, MRN, details and original fields.
- `unmatched_rows.csv`: original fields for rows lacking a PatientInfo match or PatientID.
- `summary.json`: aggregate patient counts, issue counts and classifications. QC counts count issue rows, so one patient may contribute several.

Import MRN columns as **text** in R or Excel; Excel opening a CSV directly can remove leading zeros even though the file preserves them. Outputs may contain PHI and stay in the research location. No workbook or output data belongs in GitHub.

Synthetic checks (from the repository root):

```bash
python3 -m unittest discover -s tests -p test_demographic_extraction.py -v
```
