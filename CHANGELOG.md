# Changelog

## 2026-10-29

- Allow inventory/categorization reruns in fixed output directories, replacing generated CSVs while preserving unrelated files.

- Extract all duplicated procedure sections with additional heading boundaries to reduce narrative/discharge spillover.
- Add item categorization and MRN/date access eligibility: retain attempted lead implants and mixed cases with qualifying permanent implants; separate leadless, ILR, temporary pacing, generator and uncertain categories.
- Preserve missing-section exclusions and ambiguous classifications for review; leave final MiHeart/R filtering for a subsequent step.

- Organized implementation in `scripts/`, automated checks in `tests/`, and workflow guides in `docs/`.
- Kept compatibility entry points for previously shared root commands.
- Added shared dependency instructions and exclusions for research data, outputs and Python cache files.
- Existing tools cover access extraction, reviewed-label reconciliation, invalid-key review, compact discrepancy review and procedure inventories.
