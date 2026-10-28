# Access technique documentation extraction

The parser now extracts four separate techniques: **micropuncture, ultrasound, fluoroscopy, and venogram/venography**. Co-use is allowed; venography does not automatically imply fluoroscopic access. Use the general entry point (keep both Python scripts together):

```bash
python3 parse_access_techniques.py procedure_notes.csv access_technique_results.csv --include-evidence
```

The original `parse_micropuncture.py` command also produces the expanded output. Each technique has its own `_status`, `_used`, `_needs_review`, and `_mention_count` columns, plus `_evidence` when requested. `_used` is 1 for documented use, 0 for explicit non-use in the recognized context, and blank otherwise. `access_technique` lists documented positive techniques separated by semicolons; the overall `needs_review` flags any technique requiring review. The overall `mention_count` now counts mentions across all four techniques.

Ultrasound, fluoroscopy and venography require access-related language in the local sentence window. Routine lead-position fluoroscopy, fluoroscopy time, and ultrasound for effusion checks receive `mention_without_access_context` (blank `_used`, review flagged). Such mentions do not override a separate affirmative access sentence. A procedures-performed entry such as "Upper extremity venogram for venous access" counts as documented use. Bare `US` is not matched because it is ambiguous; `US-guided` is recognized. Planned, attempted, historical and conflicting mentions remain review cases. The limited local context rules can still misattribute imaging to access when both appear in the same sentence or miss access context documented in another sentence. Review evidence before final adjudication.

For the supplied example, the expected results are micropuncture=1, fluoroscopy=1 and venogram=1, with ultrasound blank/not mentioned.

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
