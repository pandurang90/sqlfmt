require_relative "keywords"

module SQLFmt
  # One lexical unit of the input. Whitespace is not a token; instead
  # newline_before records whether the source had a line break before this
  # token, which is what we need to place comments sensibly.
  #
  # Types: :word, :keyword, :quoted_ident, :string, :number, :operator,
  # :placeholder, :comma, :lparen, :rparen, :semicolon, :dot,
  # :line_comment, :block_comment
  Token = Struct.new(:type, :text, :upper, :func, :newline_before, keyword_init: true)

  # Splits SQL into tokens. It never fails: unterminated strings and comments
  # run to the end of input, and unknown characters become operators, so
  # formatting never loses input text.
  module Lexer
    # Multi-character operators, longest first.
    MULTI_OPS = %w[->> #>> <=> <= >= <> != || :: -> #> << >> @> <@ &&].freeze
    PUNCTUATION = { "," => :comma, "(" => :lparen, ")" => :rparen, ";" => :semicolon, "." => :dot }.freeze
    VALUE_TYPES = %i[word quoted_ident rparen string placeholder].freeze

    module_function

    def tokenize(src)
      toks = lex(src)
      classify(toks)
      merge_phrases(toks)
    end

    def lex(src)
      toks = []
      n = src.length
      nl = false
      i = 0
      while i < n
        c = src[i]
        if c == "\n"
          nl = true
          i += 1
          next
        end
        if " \t\r\f\v".include?(c)
          i += 1
          next
        end

        start = i
        if c == "-" && src[i + 1] == "-"
          type = :line_comment
          i = src.index("\n", i) || n
        elsif c == "/" && src[i + 1] == "*"
          type = :block_comment
          j = src.index("*/", i + 2)
          i = j ? j + 2 : n
        elsif c == "'"
          type, i = :string, scan_quoted(src, i, "'")
        elsif c == '"'
          type, i = :quoted_ident, scan_quoted(src, i, '"')
        elsif c == "`"
          type, i = :quoted_ident, scan_quoted(src, i, "`")
        elsif c == "[" && !prev_value?(toks)
          # SQL Server [bracketed identifier]; after a value it is an array subscript.
          type, i = :quoted_ident, scan_quoted(src, i, "]")
        elsif digit?(c) || (c == "." && digit?(src[i + 1]) && !prev_value?(toks))
          type, i = :number, scan_number(src, i)
        elsif ident_start?(c)
          j = i + 1
          j += 1 while j < n && ident_part?(src[j])
          # String prefixes: N'..', E'..', X'..', B'..', U&'..'
          if j - i == 1 && "NnEeXxBb".include?(c) && src[j] == "'"
            type, i = :string, scan_quoted(src, j, "'")
          elsif j - i == 1 && (c == "U" || c == "u") && src[j] == "&" && src[j + 1] == "'"
            type, i = :string, scan_quoted(src, j + 1, "'")
          else
            type, i = :word, j
          end
        elsif c == "$"
          if (finish = scan_dollar_quoted(src, i))
            type, i = :string, finish
          elsif digit?(src[i + 1])
            j = i + 1
            j += 1 while j < n && digit?(src[j])
            type, i = :placeholder, j
          else
            type, i = :operator, i + 1
          end
        elsif c == "?"
          type, i = :placeholder, i + 1
        elsif (c == ":" || c == "@") && src[i + 1] != ":" &&
              (ident_start?(src[i + 1]) || (c == "@" && src[i + 1] == "@"))
          j = i + 1
          j += 1 while j < n && (ident_part?(src[j]) || src[j] == "@")
          type, i = :placeholder, j
        elsif PUNCTUATION.key?(c)
          type, i = PUNCTUATION[c], i + 1
        else
          op = MULTI_OPS.find { |o| src[i, o.length] == o }
          type, i = :operator, i + (op ? op.length : 1)
        end

        text = src[start...i]
        text = text.sub(/[ \t\r]+\z/, "") if type == :line_comment
        toks << Token.new(type: type, text: text, newline_before: nl)
        nl = false
      end
      toks
    end

    def digit?(c)
      !c.nil? && c >= "0" && c <= "9"
    end

    def ident_start?(c)
      !c.nil? && (c == "_" || c.ord >= 0x80 || c.match?(/[A-Za-z]/))
    end

    def ident_part?(c)
      ident_start?(c) || digit?(c) || c == "$"
    end

    # Whether the previous token ends an operand, which disambiguates "." and
    # "[" (e.g. "t.5" vs ".5", "arr[1]" vs "[col]").
    def prev_value?(toks)
      !toks.empty? && VALUE_TYPES.include?(toks.last.type)
    end

    # Index just past a quoted run starting at src[i]. A doubled closing quote
    # is an escape (SQL standard). Backslash escapes are deliberately not
    # supported because they are dialect-specific.
    def scan_quoted(src, i, closer)
      j = i + 1
      while j < src.length
        if src[j] == closer
          return j + 1 unless src[j + 1] == closer

          j += 1
        end
        j += 1
      end
      src.length
    end

    def scan_number(src, i)
      j = i
      j += 1 while j < src.length && (digit?(src[j]) || src[j] == ".")
      if src[j] == "e" || src[j] == "E"
        k = j + 1
        k += 1 if src[k] == "+" || src[k] == "-"
        if digit?(src[k])
          j = k
          j += 1 while j < src.length && digit?(src[j])
        end
      end
      j
    end

    # PostgreSQL $tag$...$tag$ strings. Returns the end index, or nil.
    def scan_dollar_quoted(src, i)
      j = i + 1
      while j < src.length && src[j] != "$"
        return nil if !ident_part?(src[j]) || (j == i + 1 && digit?(src[j]))

        j += 1
      end
      return nil if j >= src.length

      tag = src[i..j]
      k = src.index(tag, j + 1)
      k ? k + tag.length : src.length
    end

    # Promotes words to keywords. A word adjacent to "." is always an
    # identifier (t.order, key.name), and function names only count when they
    # are actually called, so a column named "count" stays as written.
    def classify(toks)
      toks.each_with_index do |t, i|
        next unless t.type == :word
        next if (i > 0 && toks[i - 1].type == :dot) || toks[i + 1]&.type == :dot

        up = t.text.upcase
        called = toks[i + 1]&.type == :lparen
        next unless KEYWORDS.include?(up) || (called && FUNCTIONS.include?(up))

        t.type = :keyword
        t.upper = up
        t.func = called && FUNCTIONS.include?(up)
      end
    end

    # Joins adjacent keywords into multi-word keywords such as
    # "LEFT OUTER JOIN" so the formatter can treat them as a single unit.
    def merge_phrases(toks)
      out = []
      i = 0
      while i < toks.length
        t = toks[i]
        if t.type == :keyword
          phrase = PHRASES.find { |p| match_phrase?(toks, i, p) }
          if phrase
            t = t.dup
            t.text = toks[i, phrase.length].map(&:text).join(" ")
            t.upper = phrase.join(" ")
            i += phrase.length - 1
          end
        end
        out << t
        i += 1
      end
      out
    end

    def match_phrase?(toks, i, phrase)
      phrase.each_with_index.all? do |w, k|
        tok = toks[i + k]
        tok && tok.type == :keyword && tok.upper == w
      end
    end
  end
end
