require_relative "sqlfmt/formatter"

# Formats SQL text into a consistent, readable layout.
#
#   SQLFmt.format("select a,b from t where x=1")
#   SQLFmt.format(sql, indent: "\t", keyword_case: :lower)
module SQLFmt
  def self.format(src, indent: "  ", keyword_case: :upper)
    Formatter.new(indent: indent, keyword_case: keyword_case).format(src)
  end

  def self.tokenize(src)
    Lexer.tokenize(src)
  end
end
