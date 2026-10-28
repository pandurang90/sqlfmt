---
paths:
  - "**/*.rb"
  - "bin/sqlfmt"
---

# Ruby style

- Standard library only. Don't add a Gemfile or any runtime gem.
- Code must run warning-free under `ruby -w` on Ruby 3.0+.
- Data holders are `Struct`s with `keyword_init: true`; constants are frozen (`.freeze`, or `Set`s built with `word_set`).
- Mutable buffers start as `+""`, since string literals may be frozen.
- Match the existing comment style: a short comment on each method saying what it decides and why, and inline comments only for non-obvious cases, naming the SQL they handle.
