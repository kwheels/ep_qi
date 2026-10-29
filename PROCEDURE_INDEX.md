# Procedure inventory

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

The extractor uses only the first `PROCEDURES PERFORMED:` section ending at the next `ANESTHESIA:` (or `ANAESTHESIA:`). Missing boundaries produce no extracted items and a review flag, rather than scanning unrelated narrative. Multiple sections are flagged. Bulleted/numbered items are separated and wrapped lines joined. Without bullets the section is retained as one provisional item and flagged; it may contain several procedures needing manual splitting. Very unusual bullet styles may also need review.

Index labels strip text after the first colon, which commonly contains device manufacturer/model/serial details, normalize whitespace and group case-insensitively. This is an explicit first-pass grouping, not a clinical taxonomy: similar labels with different wording remain separate. Check `procedure_items.csv` before combining labels or applying exclusions. The complete original item is preserved, so no model-specific distinctions are irreversibly lost.

A procedure containing a loop-recorder item and another intervention must be reviewed as a whole; the keyword flag does not mean loop-recorder-only or prove the absence of venous access. Counts refer to procedures/components documented in this partial notes collection, not the entire database. Totals across procedure labels overlap because multiple components can occur in one procedure. No cohort or R analysis is changed.

Output directory must be new. Outputs may contain PHI and remain local; do not upload them to GitHub. Use the original notes CSV containing `full_note`, not `access_technique_reviewed.csv`.

```bash
python3 -m unittest -v test_index_procedures.py
```
