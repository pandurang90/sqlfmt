---
paths:
  - "lib/**/*.rb"
---

# Formatter and lexer rules

- Layout rules only request line breaks by setting `@pending` (an indent level). Only `write` and `comment` write to `@cur`. Don't append to the output anywhere else.
- Clause rules apply only in `:block` frames. Check `top.kind` before adding a rule, so it doesn't fire inside function calls, `IN (...)` lists or `OVER (...)`.
- Prefer data over branches: a new keyword, phrase or clause goes into a table in `keywords.rb`. A new `if` in `keyword` or `clause?` needs a comment naming the SQL it exists for (e.g. `# IS DISTINCT FROM`).
- Keep `clause?` the single answer to "does this keyword start a clause here?". `keyword` and `line_start_indent` both depend on it.
- `lex` must consume at least one character in every branch, and must turn unknown or unterminated input into a token instead of raising.
- Lexer branch order is part of the logic (`--` before `-`, `->>` before `->`, string prefixes before plain words). When adding a branch, place it deliberately and add a lexer test for the case it could be confused with.
- Don't add data types to `KEYWORDS`. They are often used as column names (`date`, `text`), and uppercasing an identifier is worse than leaving a type lowercase.
