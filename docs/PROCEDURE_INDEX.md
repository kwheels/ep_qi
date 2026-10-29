# Procedure inventory

## Categorization and access cohort

Regenerate the inventory with the updated extractor, then categorize it:

```bash
python3 scripts/index_procedures.py \
  /home/kwheels/cied_complications/device_procedure_note_reconstruction/device_procedure_note_reconstruction/04_best_device_procedure_note_per_index_procedure.csv \
  --out-dir /home/kwheels/cied_complications/procedure_inventory_v2

python3 scripts/categorize_procedures.py \
  /home/kwheels/cied_complications/procedure_inventory_v2 \
  --out-dir /home/kwheels/cied_complications/procedure_categories_v1
```

The extractor now processes **all** matching sections, bounded by the next anesthesia heading, another recognized section heading, or the next procedures heading. Missing reliable end boundaries remain flagged and are not scanned to the end of the note. Original sections/items are retained and unique procedure counts do not inflate for duplicate sections. Alternative boundaries and duplicate sections remain in the extraction audit. These rules reduce, but do not guarantee elimination of, unrelated text in malformed notes.

Categorization produces:

- `categorized_procedure_index.csv`: labels, proposed categories, qualifying flags, unique MRN/date counts and a blank `reviewed_category` field for review. The same label can have different categories when full original device descriptions differ. Edits in `reviewed_category` are for review only; automatic application is not implemented.
- `procedure_eligibility.csv`: one row per MRN/date, aggregating all notes/items; includes `note_access_eligible`, supporting labels, all categories and review flags.
- `procedure_eligibility_review.csv`: uncertain categories and parsing issues to adjudicate.
- `excluded_missing_sections.csv`: procedures with no requested section in any source note. These are excluded from note-derived eligibility but preserved in an audit. The count is measured from the input, not hardcoded as four.
- `categorized_items.csv`: every original item with its proposed category.

Rules reflect the requested cohort:

- Permanent transvenous pacemaker/ICD insertion and transvenous lead insertion qualify.
- Attempted/unsuccessful transvenous lead implants qualify.
- ILR insertion/removal, leadless devices, temporary pacing and EP studies alone do not qualify. Their presence does not override a separate qualifying permanent implant item in the same procedure.
- Full item text is checked for leadless terminology, including Aveir/Micra, even when the shortened index label only says pacemaker insertion.
- Generator-only/change items are separately flagged with `generator_miheart_check`; final generator-change exclusion still needs the MiHeart/R step. Generator insertion alone is not evidence of new transvenous lead access.
- Lead revision/reposition without explicit insertion, subcutaneous/epicardial systems, generic device descriptions and unknown wording remain manual-review categories.

`note_access_eligible` is 1 for a documented qualifying component, 0 for missing-section exclusions or no qualifying component among otherwise recognized items, and blank when unresolved labels/parsing prevent a decision. `needs_review` can still be 1 when the flag is 1; review uncertainty before applying the cohort filter. These are **proposed note-based labels**, not a modification to the R analysis or a final clinical adjudication. No whole-database exclusions occur here.

The original roughly 200 index entries are distinct text labels/components, not 200 independent patient procedures. Different labels may refer to the same procedure type, and one procedure can contribute multiple categories.

Run from `ep_qi` after `git pull`. Requires only Python 3.6+ and the accompanying `reconcile_access.py`.

```bash
python3 index_procedures.py \
  /home/kwheels/cied_complications/device_procedure_note_reconstruction/device_procedure_note_reconstruction/04_best_device_procedure_note_per_index_procedure.csv \
  --out-dir /home/kwheels/cied_complications/procedure_inventory_v1
```

Start with **procedure_index.csv**, a frequency-sorted index of procedure labels with a blank `review_category` column for your classifications:

- `procedure_count`: distinct MRN/date procedures containing that label. A repeated note or repeated label in the same procedure counts once.
- `patient_count`: distinct normalized MRNs containing that label.
- `source_note_count`: input records containing the label.
- `item_mention_count`: listed item occurrences, including repeated items/notes.
- `invalid_key_note_count`: notes with unusable MRN/date keys, excluded from distinct procedure/patient counts.
- `loop_recorder_term`: keyword review aid for loop recorder/implantable cardiac monitor/ILR/ICM terminology. This does not exclude a procedure.

Other outputs:

- `procedure_records.csv`: one row per original source note, MRN, procedure date, note ID, list of labels, number of listed items, distinct label count, loop-recorder mention flag, original section and extraction-review flags.
- `procedure_items.csv`: one row per listed item, with complete original text and the normalized label. This preserves manufacturer/model/serial information for local review.
- `procedure_extraction_review.csv`: source notes with missing boundaries, empty sections, multiple matching sections, uncertain unbulleted splitting or invalid keys.

The extractor reads all `PROCEDURES PERFORMED:` sections using the boundaries described above. Bulleted/numbered items are separated and wrapped lines joined. Without bullets a section is retained as one provisional item and flagged; it may contain several procedures needing manual splitting. Very unusual bullet styles may also need review.

Index labels strip text after the first colon, which commonly contains device manufacturer/model/serial details, normalize whitespace and group case-insensitively. This is an explicit first-pass grouping, not a clinical taxonomy: similar labels with different wording remain separate. Check `procedure_items.csv` before combining labels or applying exclusions. The complete original item is preserved, so no model-specific distinctions are irreversibly lost.

A procedure containing a loop-recorder item and another intervention must be reviewed as a whole; the keyword flag does not mean loop-recorder-only or prove the absence of venous access. Counts refer to procedures/components documented in this partial notes collection, not the entire database. Totals across procedure labels overlap because multiple components can occur in one procedure. No cohort or R analysis is changed.

Output directory must be new. Outputs may contain PHI and remain local; do not upload them to GitHub. Use the original notes CSV containing `full_note`, not `access_technique_reviewed.csv`.

```bash
python3 -m unittest discover -s tests -p test_index_procedures.py -v
```
