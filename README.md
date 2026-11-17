# CIED procedure analysis utilities

Python tools for extracting procedure-note information and comparing reviewed access techniques with the procedure databases. Research inputs and generated results stay outside version control.

## Repository layout

```text
scripts/           Implementation and command-line tools
analysis/          R analysis and note-merge helpers
demographic_extraction/  Multi-tab patient workbook extraction
tests/             Automated checks using synthetic data
docs/              Usage instructions and field definitions
requirements.txt   Excel-reader dependency
```

Small Python files at the repository root preserve previously shared commands. They delegate to `scripts/`; make future implementation changes in `scripts/` only. New tools should be added there, without another root compatibility file.

## Workflows

| Task | Script | Instructions |
| --- | --- | --- |
| Extract access techniques | `scripts/parse_access_techniques.py` | [Access extraction](docs/ACCESS_EXTRACTION.md) |
| Clean reviewed labels and compare databases | `scripts/reconcile_access.py` | [Reconciliation](docs/RECONCILIATION.md) |
| Make a compact discrepancy review | `scripts/format_access_review.py` | [Reconciliation](docs/RECONCILIATION.md#compact-discrepancy-review) |
| Index procedures performed | `scripts/index_procedures.py` | [Procedure inventory](docs/PROCEDURE_INDEX.md) |
| Categorize procedures and propose access eligibility | `scripts/categorize_procedures.py` | [Categorization](docs/PROCEDURE_INDEX.md#categorization-and-access-cohort) |
| R analysis with note eligibility and anything-counts access | `analysis/ptx_analysis_v2.R` | [R note enrichment](docs/R_NOTE_ENRICHMENT.md) |
| HRS abstract counts, demographics and three chi-squared tests | `analysis/hrs_abstract_analysis.R` | [Abstract analysis](docs/HRS_ABSTRACT_ANALYSIS.md) |
| Export specific saved analysis cases | `scripts/export_analysis_cases.py` | [Abstract analysis](docs/HRS_ABSTRACT_ANALYSIS.md) |
| Redraw abstract access figures | `analysis/plot_access_results.R` | [Abstract figures](docs/HRS_ABSTRACT_ANALYSIS.md#abstract-figures) |
| Extract demographics and repeated patient data | `demographic_extraction/extract_demographics.py` | [Demographic extraction](demographic_extraction/README.md) |

Run from the repository root on Armis2:

```bash
git pull
python3 -m pip install --user -r requirements.txt
python3 scripts/index_procedures.py --help
```

Keep output folders under `/home/kwheels/cied_complications/`. Procedure inventory and categorization tools reuse existing directories, replacing their named generated CSVs and preserving unrelated files. Regeneration also resets editable review columns in those generated files; save reviewed copies under another filename. Other tools retain their documented overwrite behavior. Keep original source files unchanged. Do not commit patient notes, identifiers, Excel workbooks or generated CSVs. `.gitignore` excludes common research data/output formats; still inspect staged files before committing.

## Testing

```bash
python3 -m unittest discover -s tests -v
```

These tests use synthetic examples. They verify expected code behavior, not clinical validity or extraction accuracy across real notes.

## Adding or changing a tool

Place implementations in `scripts/`, synthetic tests in `tests/`, and usage/column definitions in `docs/`. Update this workflow table and [CHANGELOG.md](CHANGELOG.md) when behavior changes. Preserve existing command compatibility when practical. Keep real patient examples and generated results local.
