# sqlfmt

SQL formatter in Ruby, standard library only. The pipeline is lexer → token-stream formatter; there is no parser and no syntax tree. See `README.md` for the design, style decisions and known limitations.

## Commands

```sh
for f in test/test_*.rb; do ruby -w "$f"; done                 # run all tests (must be warning-free)
ruby -w test/test_formatter.rb -n /comment/                    # run tests whose name matches
bin/sqlfmt examples/reporting.sql                              # format a file
for f in examples/*.sql; do bin/sqlfmt "$f" > "examples/formatted/$(basename $f)"; done   # regenerate snapshots
```

## Where changes go

| Change | Place |
|---|---|
| New keyword, function or multi-word phrase | `lib/sqlfmt/keywords.rb` |
| Clause, join, `AND`/`OR` or `CASE` line breaks | `keyword`, `clause?`, `line_start_indent` in `lib/sqlfmt/formatter.rb` |
| Comma or parenthesis layout | `emit`, `open_paren`, `close_paren` in `lib/sqlfmt/formatter.rb` |
| Spacing between tokens | `space_before?` in `lib/sqlfmt/formatter.rb` |
| New token syntax | `lex` in `lib/sqlfmt/lexer.rb` (branch order matters) |
| CLI options | `bin/sqlfmt` |

## Invariants (never break these)

1. **Whitespace only.** Formatting never adds, removes or reorders tokens, and never changes an identifier, string or comment. `test_preserves_tokens` enforces this.
2. **Idempotent.** `format(format(x)) == format(x)`. `test_idempotent` and the example snapshots enforce this.
3. **Never raises on any SQL input.** Unknown or broken syntax passes through unchanged; it must not crash.
4. **Standard library only.** No gems at runtime; tests use minitest, which ships with Ruby.

## Before finishing a change

- Run all test files with `ruby -w`. All must pass with no warnings.
- If a change alters formatted output, add a golden case to `test/test_formatter.rb` covering it, regenerate the snapshots, and review `git diff examples/formatted` line by line.
- Update `README.md` (style decisions or known limitations) when behaviour changes.
