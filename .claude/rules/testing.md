---
paths:
  - "test/**/*.rb"
  - "examples/**/*.sql"
---

# Testing rules

- Every behaviour change gets a golden case in `CASES` in `test/test_formatter.rb`. `CASES` inputs also feed the idempotency and token-preservation tests automatically.
- Inputs that test robustness rather than layout (broken, unusual or hostile SQL) go in `CORPUS`. They are checked by the two property tests only.
- Snapshots in `examples/formatted/` are produced by the tool itself, so they can lock in bugs. Never regenerate them without reading the diff. A snapshot change that wasn't intended is a bug, not something to update.
- Each file in `examples/` should show one area of SQL. A new example needs a row in the Examples table in `README.md`.
- Never weaken `test_preserves_tokens` or `test_idempotent` to make a change pass. Fix the formatter instead.
