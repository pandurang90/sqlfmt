# sqlfmt (Ruby)

A SQL formatter in Ruby, using only the standard library (`set`, `optparse`, and `minitest` for tests, which ships with Ruby). It takes SQL in any shape (minified, hand-written, inconsistently indented) and returns it in one consistent layout.

`examples/reporting.sql` is an inconsistently formatted query:

```sql
-- Top customers in the last 30 days
with recent as (select * from orders where created_at > now() - interval '30 days' and status <> 'cancelled')
select u.id, u.name, count(o.id) as order_count, sum(o.total) total,
case when sum(o.total) > 1000 then 'gold' when sum(o.total) > 100 then 'silver' else 'bronze' end as tier
from users u left join recent o on o.user_id = u.id where u.active = 1 and u.age between 18 and 65
group by u.id, u.name having count(o.id) > 5 order by total desc limit 10;
```

`bin/sqlfmt examples/reporting.sql` prints:

```sql
-- Top customers in the last 30 days
WITH
  recent AS (
    SELECT
      *
    FROM
      orders
    WHERE
      created_at > NOW() - INTERVAL '30 days'
      AND status <> 'cancelled'
  )
SELECT
  u.id,
  u.name,
  COUNT(o.id) AS order_count,
  SUM(o.total) total,
  CASE
    WHEN SUM(o.total) > 1000 THEN 'gold'
    WHEN SUM(o.total) > 100 THEN 'silver'
    ELSE 'bronze'
  END AS tier
FROM
  users u
  LEFT JOIN recent o ON o.user_id = u.id
WHERE
  u.active = 1
  AND u.age BETWEEN 18 AND 65
GROUP BY
  u.id,
  u.name
HAVING
  COUNT(o.id) > 5
ORDER BY
  total DESC
LIMIT 10;
```

## Usage

```
bin/sqlfmt [options] [file ...]     # reads stdin when no files are given

    --indent N     spaces per indentation level (default 2)
    --tabs         indent with tabs instead of spaces
    --case CASE    keyword case: upper, lower, or preserve (default upper)
-w, --write        write result back to each file instead of stdout
```

```sh
bin/sqlfmt query.sql             # print the formatted file
bin/sqlfmt a.sql b.sql           # several files, printed in order
bin/sqlfmt -w a.sql b.sql        # rewrite the files in place
pbpaste | bin/sqlfmt             # or pipe SQL in on stdin
```

Arguments are always file paths, never SQL text. SQL passed on the command line runs into shell quoting problems: `"... id = $1"` has `$1` expanded by the shell, and `'it''s'` ends the shell string early. Arguments are also limited in length (`ARG_MAX`). Reading files and stdin avoids both, and it follows the same convention as standard Unix filters like `jq` and `sort`.

As a library:

```ruby
require_relative "lib/sqlfmt"
SQLFmt.format(sql)                                   # 2 spaces, uppercase keywords
SQLFmt.format(sql, indent: "\t", keyword_case: :lower)
```

Run the tests (Ruby 3.0+):

```sh
for f in test/test_*.rb; do ruby -w "$f"; done
```

## Layout

| File | Role |
|---|---|
| `lib/sqlfmt/lexer.rb` | Splits SQL into tokens, classifies keywords, merges multi-word keywords |
| `lib/sqlfmt/keywords.rb` | Keyword, function and clause tables that drive casing and line breaks |
| `lib/sqlfmt/formatter.rb` | Walks tokens with a frame stack and lays them out |
| `lib/sqlfmt.rb` | Public API: `SQLFmt.format`, `SQLFmt.tokenize` |
| `bin/sqlfmt` | CLI |
| `test/` | Golden tests, lexer tests, idempotency and token-preservation properties, example snapshots |
| `examples/` | Sample inputs (`*.sql`) and their reviewed formatted output (`formatted/*.sql`) |

## Examples

Each file in `examples/` covers one area, and `examples/formatted/` holds its formatted output. `test/test_examples.rb` checks that the tool still produces exactly that output.

| Example | Shows |
|---|---|
| `reporting.sql` | CTE, `CASE`, join, `BETWEEN`, `GROUP BY` / `HAVING`, header comment |
| `ddl.sql` | `CREATE TABLE` with constraints, `CREATE OR REPLACE VIEW` |
| `subqueries.sql` | Subqueries nested three deep in `FROM`, the select list and `WHERE`; `EXISTS`; `UNION` |
| `window_functions.sql` | `OVER (PARTITION BY … ORDER BY …)`, window frames |
| `comments.sql` | Block, own-line and trailing comments keep their positions |
| `tricky.sql` | Keywords inside strings and quoted identifiers, casts, JSON operators, placeholders, dollar-quoted and prefixed strings, non-ASCII text |

The snapshots record current behaviour, including its rough edges. See [Known limitations](#known-limitations).

After an intentional formatting change, regenerate the snapshots and review the diff:

```sh
for f in examples/*.sql; do bin/sqlfmt "$f" > "examples/formatted/$(basename $f)"; done
git diff examples/formatted
```

## Approach

The pipeline has two stages: **lexer → token-stream formatter**. There is no AST.

1. **Lexer.** This is the part that has to be exactly right, because every other step depends on it. It handles:
   - single-quoted strings with `''` escapes, plus `E''`, `N''`, `X''` and `U&''` prefixes and Postgres `$tag$…$tag$` strings
   - quoted identifiers in `"…"`, `` `…` `` and `[…]`
   - `--` and `/* */` comments
   - numbers, including `.5` and `1e-3`
   - multi-character operators such as `::`, `->>`, `<>` and `||`
   - placeholders: `?`, `$1`, `:name` and `@var`

   Keywords inside strings, comments or quoted identifiers are never touched. Each token records whether a newline came before it in the source; comment placement uses this and nothing else does.

2. **Formatter.** It walks the tokens with a small stack of frames:
   - **block**: the statement level, or a parenthesised subquery. Clauses start lines here, and list items and `AND`/`OR` conditions get their own lines.
   - **inline**: a function call, an `IN (…)` list, `OVER (…)` or an expression group. Everything inside stays on one line.
   - **list**: a `CREATE TABLE` column list, with one column per line.
   - **case**: `CASE … END`. It is multi-line in block context and inline inside a function call such as `SUM(CASE …)`.

   Most layout decisions come down to "which frame am I in?". For example, `ORDER BY` inside `OVER (…)` stays inline, but `ORDER BY` in a subquery starts a line.

### Why not a parser?

A real SQL parser means picking one dialect, and it fails on input it doesn't understand. A formatter gets used on vendor-specific, partial or even broken SQL. Working on tokens means it degrades gracefully: unknown syntax still comes out with every token intact and reasonable spacing, just less structured layout.

### Correctness strategy

- **Golden tests** pin down the layout for each construct.
- **Token preservation property:** lexing the input and lexing the output give the same token sequence, ignoring keyword case. A formatter must never change a query's meaning.
- **Idempotency property:** `format(format(x)) == format(x)`. Without it, format-on-save and CI checks would keep flipping the file back and forth.
- **Example snapshots:** each file in `examples/` must format exactly to its copy in `examples/formatted/`, and formatting that output again must not change it (see [Examples](#examples)).

The corpus includes hostile input: unterminated strings and comments, unbalanced parentheses, `;;`, non-ASCII identifiers. The formatter never raises on any input.

## Style decisions

- Each major clause keyword (`SELECT`, `FROM`, `WHERE`, `GROUP BY`, `ORDER BY`, `HAVING`, `SET`, `VALUES`, `WITH`, `RETURNING`) goes on its own line, with its contents indented below it. Comma-separated items get one line each.
- Short clauses keep their argument on the same line: `LIMIT 10`, `INSERT INTO t (a, b)`, `UPDATE t`, `DELETE FROM t`.
- `JOIN`s are indented under `FROM`. `ON` stays on the `JOIN` line, and extra `AND`/`OR` join conditions go one level deeper.
- The `AND` in `BETWEEN x AND y` is recognised and kept inline.
- Keywords are uppercased. Function names are uppercased **only when called**, so a column named `count` is left alone. Identifiers are never re-cased.
- Data type names are deliberately not treated as keywords, because they are often used as column names (`date`, `text`).
- A comment on its own line stays on its own line, and a trailing comment stays trailing.
- Statements are separated by a blank line.

## Known limitations

- **No line-width awareness.** Long inline expressions stay on one line, and even short queries take several lines.
- **Dialect coverage is pragmatic.** It handles common ANSI SQL, Postgres and MySQL syntax. `MERGE` and procedural blocks pass through safely but get little structure.
- **Keywords used as column names get uppercased.** `KEY` is a keyword so that `PRIMARY KEY` is uppercased, which means a column named `key` becomes `KEY`. The token-preservation test ignores keyword case, so it doesn't catch this.
- Keywords from other dialects are passed through as written. Snowflake's `QUALIFY` stays lowercase on the `WHERE` line (`window_functions.sql`), and `at time zone` stays lowercase (`tricky.sql`).
- `AND`/`OR` breaks don't show precedence.

## What I'd build next

1. Line-width–aware wrapping (Wadler/Prettier-style), so short queries stay on one line.
2. A dialect option controlling string escapes, quoting rules and extra keywords.
3. Property-based fuzzing, using token preservation and idempotency as the oracle.
