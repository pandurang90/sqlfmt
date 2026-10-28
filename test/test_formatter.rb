require "minitest/autorun"
require_relative "../lib/sqlfmt"

class TestFormatter < Minitest::Test
  CASES = {
    "simple select" => ["select a,b from t where x=1", <<~SQL],
      SELECT
        a,
        b
      FROM
        t
      WHERE
        x = 1
    SQL

    "joins and conditions" => [
      "SELECT u.id FROM users u LEFT OUTER JOIN orders o ON o.uid=u.id AND o.ok INNER JOIN x USING (id) WHERE a=1 AND (b=2 OR c=3) OR d",
      <<~SQL
        SELECT
          u.id
        FROM
          users u
          LEFT OUTER JOIN orders o ON o.uid = u.id
            AND o.ok
          INNER JOIN x USING (id)
        WHERE
          a = 1
          AND (b = 2 OR c = 3)
          OR d
      SQL
    ],

    "between keeps its AND inline" => ["select * from t where a between 1 and 10 and b = 2", <<~SQL],
      SELECT
        *
      FROM
        t
      WHERE
        a BETWEEN 1 AND 10
        AND b = 2
    SQL

    "group order having limit" => [
      "select a, count(*) from t group by a having count(*)>1 order by 2 desc, a limit 5 offset 10",
      <<~SQL
        SELECT
          a,
          COUNT(*)
        FROM
          t
        GROUP BY
          a
        HAVING
          COUNT(*) > 1
        ORDER BY
          2 DESC,
          a
        LIMIT 5
        OFFSET 10
      SQL
    ],

    "subquery in where and from" => ["select x from (select 1 as x) s where x in (select y from z)", <<~SQL],
      SELECT
        x
      FROM
        (
          SELECT
            1 AS x
        ) s
      WHERE
        x IN (
          SELECT
            y
          FROM
            z
        )
    SQL

    "cte with recursive" => ["with recursive a as (select 1), b as (select 2) select * from a, b", <<~SQL],
      WITH RECURSIVE
        a AS (
          SELECT
            1
        ),
        b AS (
          SELECT
            2
        )
      SELECT
        *
      FROM
        a,
        b
    SQL

    "case expression" => [
      "select case when a=1 then 'one' when a=2 then 'two' else 'many' end as n, sum(case when b then 1 else 0 end) from t",
      <<~SQL
        SELECT
          CASE
            WHEN a = 1 THEN 'one'
            WHEN a = 2 THEN 'two'
            ELSE 'many'
          END AS n,
          SUM(CASE WHEN b THEN 1 ELSE 0 END)
        FROM
          t
      SQL
    ],

    "window function stays inline" => ["select row_number() over (partition by a order by b desc) from t", <<~SQL],
      SELECT
        ROW_NUMBER() OVER (PARTITION BY a ORDER BY b DESC)
      FROM
        t
    SQL

    "insert values" => ["insert into t(a,b) values (1,'x'),(2,'y')", <<~SQL],
      INSERT INTO t (a, b)
      VALUES
        (1, 'x'),
        (2, 'y')
    SQL

    "update and delete, multiple statements" => ["update t set a=-1,b=b+1 where id=3;delete from t where id=4;", <<~SQL],
      UPDATE t
      SET
        a = -1,
        b = b + 1
      WHERE
        id = 3;

      DELETE FROM t
      WHERE
        id = 4;
    SQL

    "create table" => [
      "create table foo (id int primary key, name varchar(10) not null, foreign key (a) references b(id) on delete cascade)",
      <<~SQL
        CREATE TABLE foo (
          id int PRIMARY KEY,
          name varchar(10) NOT NULL,
          FOREIGN KEY (a) REFERENCES b(id) ON DELETE CASCADE
        )
      SQL
    ],

    "union" => ["select a from t union all select b from u", <<~SQL],
      SELECT
        a
      FROM
        t
      UNION ALL
      SELECT
        b
      FROM
        u
    SQL

    "comments are preserved and placed" => ["-- header\nselect a, -- first\n  /* second */ b\nfrom t -- tbl\nwhere x = 1", <<~SQL],
      -- header
      SELECT
        a, -- first
        /* second */ b
      FROM
        t -- tbl
      WHERE
        x = 1
    SQL

    "own-line comment inside select list" => ["select\n-- the id\nid, name from t", <<~SQL],
      SELECT
        -- the id
        id,
        name
      FROM
        t
    SQL

    "own-line comments line up with the clause, join or condition below" => [
      "select a, b\n-- source table\nfrom t\n-- join users\njoin u on u.id = t.uid\n" \
      "-- only active\nwhere x = 1\n-- and recent\nand y between 1 and 2",
      <<~SQL
        SELECT
          a,
          b
        -- source table
        FROM
          t
          -- join users
          JOIN u ON u.id = t.uid
        -- only active
        WHERE
          x = 1
          -- and recent
          AND y BETWEEN 1 AND 2
      SQL
    ],

    "keywords inside strings and identifiers untouched" => [%q(select 'select from where', "order", t.select, [group] from t), <<~SQL],
      SELECT
        'select from where',
        "order",
        t.select,
        [group]
      FROM
        t
    SQL

    "operators casts placeholders" => [
      "select a::text, b||c, -d, x->>'k' from t where e>=$1 and f<>? and g = :name and h != @v",
      <<~SQL
        SELECT
          a::text,
          b || c,
          -d,
          x ->> 'k'
        FROM
          t
        WHERE
          e >= $1
          AND f <> ?
          AND g = :name
          AND h != @v
      SQL
    ],

    "function names only uppercased when called" => ["select count, count(*), max(x) from t", <<~SQL],
      SELECT
        count,
        COUNT(*),
        MAX(x)
      FROM
        t
    SQL

    "is distinct from and for update are not clauses" => ["select a from t where a is distinct from b for update", <<~SQL],
      SELECT
        a
      FROM
        t
      WHERE
        a IS DISTINCT FROM b FOR UPDATE
    SQL

    "empty input" => ["  \n ", ""]
  }.freeze

  CASES.each do |name, (input, want)|
    define_method("test_#{name.gsub(/\W+/, '_')}") do
      assert_equal want, SQLFmt.format(input), "input: #{input}"
    end
  end

  def test_keyword_case
    assert_equal "select\n  a\nfrom\n  t\n", SQLFmt.format("Select a From t", keyword_case: :lower)
    assert_equal "Select\n\ta\nFrom\n\tt\n", SQLFmt.format("Select a From t", indent: "\t", keyword_case: :preserve)
    assert_raises(ArgumentError) { SQLFmt.format("x", keyword_case: :shout) }
  end

  # Every test input plus some messier SQL, used for property tests.
  CORPUS = CASES.values.map(&:first) + [
    "SELECT\n\n   a\n,b   FROM t;;",
    "select (((1))) , f(g(h(x, y)), z) from t where not exists(select 1)",
    "select $$it's a $body$ string$$, E'esc''d', N'unicode' from dual",
    "select 'unterminated",
    "select /* unterminated",
    "select a from t where (select max(b) from u where u.x = t.x) > 3 and c in (1,2,3)",
    "select case x when 1 then case when y then 'a' else 'b' end else 'c' end from t",
    "select a ) from t", # unbalanced paren
    "insert into t select * from u on conflict (id) do update set a = excluded.a returning id",
    "select arr[1], .5, 1.5e-3, a.b.c from t",
    "select ünïcödé, naïve from café"
  ].freeze

  # Formatting already-formatted SQL must be a no-op, otherwise editor
  # integrations and CI checks would flap.
  def test_idempotent
    CORPUS.each do |input|
      once = SQLFmt.format(input)
      assert_equal once, SQLFmt.format(once), "not idempotent for #{input.inspect}"
    end
  end

  # A formatter must never change what the SQL means: the token sequence must
  # be identical before and after, ignoring keyword case and whitespace.
  def test_preserves_tokens
    signature = lambda do |src|
      SQLFmt.tokenize(src).map do |tok|
        # Unterminated strings/comments run to EOF and absorb the trailing
        # newline; that whitespace is not meaningful.
        tok.type == :keyword ? tok.upper : tok.text.sub(/\n+\z/, "")
      end
    end
    CORPUS.each do |input|
      [{}, { indent: "\t", keyword_case: :lower }].each do |opts|
        out = SQLFmt.format(input, **opts)
        assert_equal signature.call(input), signature.call(out), "tokens changed for #{input.inspect}"
      end
    end
  end
end
