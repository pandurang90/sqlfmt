require "set"

module SQLFmt
  def self.word_set(words)
    words.split(",").map(&:strip).to_set.freeze
  end

  # Reserved words that get case-normalized. Data type names are intentionally
  # left out: they are commonly used as column names (date, text, timestamp),
  # and uppercasing an identifier is worse than leaving a type as written.
  KEYWORDS = word_set(<<~W)
    SELECT, FROM, WHERE, AND, OR, NOT, IN, IS, NULL, LIKE, ILIKE, BETWEEN,
    EXISTS, AS, ON, JOIN, INNER, LEFT, RIGHT, FULL, OUTER, CROSS, NATURAL, USING,
    GROUP, BY, ORDER, HAVING, LIMIT, OFFSET, UNION, ALL, INTERSECT, EXCEPT, DISTINCT,
    INSERT, INTO, VALUES, UPDATE, SET, DELETE, CREATE, REPLACE, TABLE, VIEW,
    INDEX, ALTER, DROP, ADD, COLUMN, PRIMARY, KEY, FOREIGN, REFERENCES, DEFAULT,
    CONSTRAINT, UNIQUE, CHECK, CASE, WHEN, THEN, ELSE, END, ASC, DESC, WITH,
    RECURSIVE, OVER, PARTITION, ROWS, RANGE, UNBOUNDED, PRECEDING, FOLLOWING,
    CURRENT, ROW, TRUE, FALSE, IF, RETURNING, CONFLICT, DO, NOTHING, FETCH, FIRST,
    NEXT, ONLY, LATERAL, ANY, SOME, NULLS, LAST, INTERVAL, FOR, CASCADE, TRUNCATE
  W

  # Function names, uppercased only when directly followed by "(".
  FUNCTIONS = word_set(<<~W)
    COUNT, SUM, AVG, MIN, MAX, COALESCE, NULLIF, CAST, EXTRACT, SUBSTRING,
    TRIM, UPPER, LOWER, LENGTH, ROUND, ABS, NOW, CONCAT, ROW_NUMBER, RANK, DENSE_RANK,
    LAG, LEAD, FIRST_VALUE, LAST_VALUE, DATE_TRUNC, LEFT, RIGHT, IF, IFNULL, ISNULL,
    GREATEST, LEAST, REPLACE, STRING_AGG, ARRAY_AGG
  W

  # Merged into a single keyword token. Longer phrases come first.
  PHRASES = [
    %w[CREATE OR REPLACE VIEW],
    %w[LEFT OUTER JOIN], %w[RIGHT OUTER JOIN], %w[FULL OUTER JOIN],
    %w[GROUP BY], %w[ORDER BY], %w[PARTITION BY],
    %w[LEFT JOIN], %w[RIGHT JOIN], %w[FULL JOIN], %w[INNER JOIN],
    %w[CROSS JOIN], %w[NATURAL JOIN],
    %w[INSERT INTO], %w[DELETE FROM], %w[UNION ALL],
    %w[CREATE TABLE], %w[CREATE VIEW], %w[ON CONFLICT]
  ].freeze

  # Start a line and put their contents on indented lines below.
  BLOCK_CLAUSES = word_set("SELECT, FROM, WHERE, GROUP BY, HAVING, ORDER BY, SET, VALUES, RETURNING, WITH")

  # Start a line and keep their contents on the same line.
  INLINE_CLAUSES = word_set(<<~W)
    LIMIT, OFFSET, INSERT INTO, UPDATE, DELETE FROM, DELETE, CREATE TABLE,
    CREATE VIEW, CREATE OR REPLACE VIEW, ON CONFLICT, UNION, UNION ALL, INTERSECT, EXCEPT, TRUNCATE
  W

  # Only clauses when not preceded by another keyword (ON DELETE CASCADE,
  # FOR UPDATE, DO UPDATE).
  STATEMENT_STARTS = word_set("INSERT INTO, UPDATE, DELETE FROM, DELETE, TRUNCATE")

  # Sit on their own line between two queries.
  SET_OPS = word_set("UNION, UNION ALL, INTERSECT, EXCEPT")

  JOINS = word_set(<<~W)
    JOIN, INNER JOIN, LEFT JOIN, RIGHT JOIN, FULL JOIN, CROSS JOIN, NATURAL JOIN,
    LEFT OUTER JOIN, RIGHT OUTER JOIN, FULL OUTER JOIN
  W

  # Put each comma-separated item on its own line.
  COMMA_BREAK_CLAUSES = word_set("SELECT, FROM, GROUP BY, ORDER BY, SET, VALUES, RETURNING, WITH")

  # Stay on the clause keyword's line: SELECT DISTINCT, WITH RECURSIVE.
  CLAUSE_MODIFIERS = word_set("DISTINCT, ALL, RECURSIVE")
end
