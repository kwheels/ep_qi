# Repository conventions

- Put implementation and new command-line tools in `scripts/`.
- Put R analyses and their helpers in `analysis/`; keep synthetic R checks in `tests/`.
- Put automated tests in `tests/`; use synthetic data only.
- Put workflow instructions and output-column definitions in `docs/`.
- Keep the root README as a short navigation guide; update its workflow table when adding tools.
- Record user-visible changes in CHANGELOG.md.
- Preserve existing command entry points when reorganizing; root Python files are compatibility wrappers, not implementation copies.
- Never stage patient data, original clinical notes, workbooks, generated results or credentials. Inspect staged paths before committing.
- Keep input files unchanged and real outputs outside the repository. The user prefers fixed reusable output folders. Inventory and categorization tools replace only their named generated files; preserve unrelated files. Other tools retain their documented overwrite behavior.
- Run `python3 -m unittest discover -s tests -v` with the Excel dependency available when relevant. Describe these as synthetic code checks, not validation on clinical data.
- Prefer the standard library; add dependencies to requirements.txt only when needed.
