# Micropuncture documentation extraction

Copy `parse_micropuncture.py` to Armis2 and run with Python 3. No additional packages or network access are needed.

```bash
python3 parse_micropuncture.py procedure_notes.csv micropuncture_results.csv
```

Optional matching excerpts for review (these may contain PHI):

```bash
python3 parse_micropuncture.py procedure_notes.csv micropuncture_review.csv --include-evidence
```

Input must be a complete CSV, with the supplied header and properly quoted multiline `full_note` cells. A pasted fragment beginning with a header followed directly by narrative is not a complete CSV record. The standard CSV reader handles embedded commas, quotes and line breaks. Default encoding is UTF-8 with optional BOM; use `--encoding cp1252` if required by the actual export. Output files must not already exist.

The output retains available procedure identifiers, both MRN columns, dates, candidate count and date difference. All identifiers remain strings, including leading zeros; import MRN columns as text when opening in Excel. One output row corresponds to one input report. Reports are not deduplicated or collapsed to patients, and candidate reports are not assumed to be confirmed matches to index procedures.

| Status | micropuncture_used | Meaning |
|---|---|---|
| documented_use | 1 | Micropuncture mention with action language |
| explicit_non_use | 0 | Recognized explicit negation |
| not_mentioned | blank | No recognized micropuncture term |
| missing_note | blank | Empty narrative; review flagged |
| uncertain_mention | blank | Ambiguous, planned, historical or attempted use; review flagged |
| mixed_mentions | blank | Different classifications within one report; review flagged |

The rules recognize `micropuncture`, `micro-puncture` and `micro puncture`, including wrapped words. Needle gauge alone is not considered evidence. These are conservative text rules, not validated clinical classifications. They do not reliably resolve all negation, historical references, procedure sections, venous versus arterial access, or multiple access sites. A documented-use label indicates an apparent affirmative mention; it does not establish successful venous access. Review flagged records and a sample of positive and no-mention records before using results to update the research database. Missing mention must not automatically become non-use. Confirm candidate report matching using the retained identifiers and dates.

Evidence excerpts are omitted by default, and console output contains aggregate counts only. Run on Armis2 with the source data there; the script does not transmit data. Outputs contain MRNs and should remain in the appropriate research location. On a malformed CSV, processing stops and the output may be incomplete; correct the input and use a new output filename.

Synthetic checks:

```bash
python3 -m unittest -v test_parse_micropuncture.py
```
