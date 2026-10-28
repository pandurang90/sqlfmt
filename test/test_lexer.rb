require "minitest/autorun"
require_relative "../lib/sqlfmt"

class TestLexer < Minitest::Test
  NAMES = {
    word: "word", keyword: "kw", quoted_ident: "qident", string: "string", number: "num",
    operator: "op", placeholder: "ph", comma: "comma", lparen: "lparen", rparen: "rparen",
    semicolon: "semi", dot: "dot", line_comment: "line", block_comment: "block"
  }.freeze

  CASES = {
    "a.b" => ["word:a", "dot:.", "word:b"],
    "'it''s'" => ["string:'it''s'"],
    %("my ""col""") => [%(qident:"my ""col""")],
    "`x`" => ["qident:`x`"],
    "[x y]" => ["qident:[x y]"],
    "arr[1]" => ["word:arr", "op:[", "num:1", "op:]"],
    "$tag$ a $ b $tag$" => ["string:$tag$ a $ b $tag$"],
    "E'x' N'y'" => ["string:E'x'", "string:N'y'"],
    "$1 ? :p @v @@rowcount" => ["ph:$1", "ph:?", "ph::p", "ph:@v", "ph:@@rowcount"],
    "a::int" => ["word:a", "op:::", "word:int"],
    "1.5e-3 .5 42" => ["num:1.5e-3", "num:.5", "num:42"],
    "<= <> != || ->> -" => ["op:<=", "op:<>", "op:!=", "op:||", "op:->>", "op:-"],
    "x -- c \ny" => ["word:x", "line:-- c", "word:y"],
    "/* a\nb */" => ["block:/* a\nb */"],
    "group  by" => ["kw:GROUP BY"],
    "left outer join" => ["kw:LEFT OUTER JOIN"],
    "t.order" => ["word:t", "dot:.", "word:order"],
    "count count(" => ["word:count", "kw:COUNT", "lparen:("]
  }.freeze

  def test_tokenize
    CASES.each do |input, want|
      got = SQLFmt.tokenize(input).map do |t|
        "#{NAMES.fetch(t.type)}:#{t.type == :keyword ? t.upper : t.text}"
      end
      assert_equal want, got, "tokenize(#{input.inspect})"
    end
  end
end
