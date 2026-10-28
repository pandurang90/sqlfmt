require_relative "lexer"

module SQLFmt
  # One level of nesting. Layout decisions are made against the innermost
  # frame: clauses only break lines in block frames, so ORDER BY inside
  # OVER (...) stays inline while ORDER BY in a subquery does not.
  #
  # Kinds:
  #   :block  - statement level, or a parenthesized subquery
  #   :list   - CREATE TABLE column list: one item per line
  #   :inline - function call, IN list, expression grouping
  #   :case   - CASE ... END
  Frame = Struct.new(
    :kind,
    :base,         # block: clause indent; list/case/inline: item indent
    :close_indent, # indent of the closing ")" or END
    :clause,       # current clause in a block frame
    :cond_indent,  # indent for AND/OR breaks, -1 when they stay inline
    :between,      # saw BETWEEN, so the next AND is part of it
    :paren_opened, # CREATE TABLE already opened its column list
    :multiline,    # case: WHEN/ELSE on their own lines
    keyword_init: true
  ) do
    def self.make(kind, base: 0, close_indent: 0, multiline: false)
      new(kind: kind, base: base, close_indent: close_indent, clause: nil, cond_indent: -1,
          between: false, paren_opened: false, multiline: multiline)
    end
  end

  # Walks the token stream and lays it out. It works on tokens rather than a
  # parse tree, tracking just enough structure (clauses, parentheses, CASE)
  # to decide where lines break and how deep they indent.
  class Formatter
    KEYWORD_CASES = %i[upper lower preserve].freeze
    INSERT_LIKE_CLAUSES = ["INSERT INTO", "CREATE TABLE", "CREATE VIEW", "CREATE OR REPLACE VIEW"].freeze

    def initialize(indent: "  ", keyword_case: :upper)
      unless KEYWORD_CASES.include?(keyword_case)
        raise ArgumentError, "keyword_case must be one of #{KEYWORD_CASES.join(', ')}"
      end

      @indent = indent
      @keyword_case = keyword_case
    end

    def format(src)
      @toks = Lexer.tokenize(src)
      @stack = [Frame.make(:block)]
      @lines = []
      @cur = +""
      @cur_indent = 0
      @pending = -1         # indent for a requested line break before the next token, -1 if none
      @must_break = false   # a line comment ended the line; next token needs a new one
      @stmt_break = false   # a statement ended; next token starts after a blank line
      @after_comment = false
      @prev = nil
      @prev_unary = false

      @pos = 0
      while @pos < @toks.length
        emit(@toks[@pos])
        @pos += 1
      end
      flush_line
      return "" if @lines.empty?

      # Stripping trailing newlines keeps the result stable when input ends
      # inside an unterminated string or comment that swallowed a newline.
      @lines.join("\n").sub(/\n+\z/, "") + "\n"
    end

    private

    def top
      @stack.last
    end

    # The next non-comment token, or nil.
    def peek
      @toks[(@pos + 1)..].find { |t| t.type != :line_comment && t.type != :block_comment }
    end

    def emit(t)
      frame = top
      case t.type
      when :line_comment, :block_comment
        comment(t)
      when :semicolon
        @stack = [Frame.make(:block)]
        # "x -- comment\n;" can't rejoin the comment's line
        @pending = @must_break ? 0 : -1
        write(t, ";")
        @stmt_break = true
      when :comma
        write(t, ",")
        if frame.kind == :block && COMMA_BREAK_CLAUSES.include?(frame.clause)
          @pending = frame.base + 1
        elsif frame.kind == :list
          @pending = frame.base
        end
      when :lparen
        open_paren(t)
      when :rparen
        close_paren(t)
      when :keyword
        keyword(t)
      else
        write(t, t.text)
      end
    end

    def open_paren(t)
      frame = top
      kind = :inline
      nx = peek
      if nx && nx.type == :keyword && %w[SELECT WITH].include?(nx.upper)
        kind = :block
      elsif frame.kind == :block && frame.clause == "CREATE TABLE" && !frame.paren_opened
        frame.paren_opened = true
        kind = :list
      end
      write(t, "(")
      fr = Frame.make(kind, base: @cur_indent + 1, close_indent: @cur_indent)
      @stack.push(fr)
      @pending = fr.base if kind == :list
    end

    def close_paren(t)
      # Unclosed CASE frames end at the enclosing paren.
      @stack.pop while @stack.length > 1 && top.kind == :case
      if @stack.length == 1 # unbalanced ")": just write it
        write(t, ")")
        return
      end
      fr = @stack.pop
      @pending = fr.close_indent if fr.kind == :block || fr.kind == :list
      write(t, ")")
    end

    def keyword(t)
      kw = t.upper
      text = keyword_text(t)
      frame = top
      prev_kw = @prev&.type == :keyword

      case kw
      when "CASE"
        write(t, text)
        multiline = frame.kind == :block || frame.kind == :list || (frame.kind == :case && frame.multiline)
        @stack.push(Frame.make(:case, base: @cur_indent + 1, close_indent: @cur_indent, multiline: multiline))
        return
      when "WHEN", "ELSE"
        @pending = frame.base if frame.kind == :case && frame.multiline
      when "END"
        if frame.kind == :case
          @stack.pop
          @pending = frame.close_indent if frame.multiline
        end
      end

      # Clause layout only applies at block level.
      if frame.kind == :block
        if clause?(t)
          @pending = frame.base
          write(t, text)
          frame.clause = kw
          frame.cond_indent = %w[WHERE HAVING].include?(kw) ? frame.base + 1 : -1
          frame.between = false
          frame.paren_opened = false
          if BLOCK_CLAUSES.include?(kw)
            @pending = frame.base + 1
          elsif SET_OPS.include?(kw)
            @pending = frame.base
          end
          return
        elsif JOINS.include?(kw)
          @pending = frame.base + 1
          write(t, text)
          frame.cond_indent = frame.base + 2
          return
        elsif kw == "BETWEEN"
          frame.between = true
        elsif kw == "AND" && frame.between
          frame.between = false
        elsif (kw == "AND" || kw == "OR") && frame.cond_indent >= 0
          @pending = frame.cond_indent
        end
      end

      # SELECT DISTINCT / WITH RECURSIVE: keep on the clause line and leave the
      # pending break for the clause's first item.
      if CLAUSE_MODIFIERS.include?(kw) && @pending >= 0 && prev_kw && BLOCK_CLAUSES.include?(@prev.upper)
        saved = @pending
        @pending = -1
        write(t, text)
        @pending = saved
        return
      end
      write(t, text)
    end

    # Whether keyword t starts a clause here, given the token before it.
    def clause?(t)
      kw = t.upper
      prev_kw = @prev&.type == :keyword
      return false unless BLOCK_CLAUSES.include?(kw) || INLINE_CLAUSES.include?(kw)
      return false if STATEMENT_STARTS.include?(kw) && prev_kw
      return false if kw == "WITH" && @prev && !%i[semicolon lparen].include?(@prev.type) # WITH TIME ZONE
      return false if kw == "FROM" && prev_kw && @prev.upper == "DISTINCT" # IS DISTINCT FROM

      true
    end

    # The indent token t will start a line at, if the layout rules give it a
    # line of its own (a clause, join or AND/OR condition), else nil.
    def line_start_indent(t)
      frame = top
      return nil unless t&.type == :keyword && frame.kind == :block

      kw = t.upper
      if clause?(t)
        frame.base
      elsif JOINS.include?(kw)
        frame.base + 1
      elsif (kw == "OR" || (kw == "AND" && !frame.between)) && frame.cond_indent >= 0
        frame.cond_indent
      end
    end

    def keyword_text(t)
      case @keyword_case
      when :lower then t.upper.downcase
      when :preserve then t.text
      else t.upper
      end
    end

    # A comment that started its own line in the input keeps its own line;
    # one that trailed code stays trailing. Line breaks the formatter had
    # already requested are kept for the next real token.
    def comment(t)
      if t.newline_before || @cur.empty?
        saved = @pending
        # A comment just above a clause, join or condition is about that
        # line, so it lines up with it rather than with what came before.
        level = line_start_indent(peek) || (saved >= 0 ? saved : cont_indent)
        level = 0 if @prev.nil?
        if @stmt_break
          blank_line
          level = 0
          @stmt_break = false
        end
        start_line(level)
        @cur << t.text
        # The requested break still applies to the next token unless that
        # token shares the comment's line ("/* note */ col").
        @must_break = next_on_new_line?(t)
        @pending = @must_break ? saved : -1
      else
        @cur << " " << t.text
        @must_break = true if next_on_new_line?(t)
      end
      @after_comment = true
    end

    # The token after comment t must start a new line: always after a line
    # comment, and after a block comment only if the source broke the line.
    def next_on_new_line?(t)
      return true if t.type == :line_comment

      nxt = @toks[@pos + 1]
      !nxt.nil? && nxt.newline_before
    end

    # Where a line continues when it had to break for a comment.
    def cont_indent
      top.kind == :block ? top.base + 1 : top.base
    end

    def write(t, text)
      if @stmt_break
        blank_line
        @stmt_break = false
        @pending = -1
        @must_break = false
      elsif @pending >= 0
        start_line(@pending)
        @pending = -1
        @must_break = false
      elsif @must_break
        start_line(cont_indent)
        @must_break = false
      end
      @cur << " " if !@cur.empty? && space_before?(t)
      @cur << text

      @prev_unary = t.type == :operator && %w[- + ~].include?(t.text) && operand_expected?
      @prev = t
      @after_comment = false
    end

    # Whether the previous token leaves us expecting an operand, which makes a
    # following "-" unary (x = -1, THEN -1, (-a)).
    def operand_expected?
      return true if @prev.nil?

      case @prev.type
      when :operator, :lparen, :comma then true
      when :keyword then !%w[END NULL TRUE FALSE].include?(@prev.upper)
      else false
      end
    end

    def space_before?(t)
      return true if @after_comment
      return false if %i[comma semicolon rparen dot].include?(t.type)

      p = @prev
      return true if p.nil?
      return false if p.type == :lparen || p.type == :dot

      if t.type == :lparen
        return false if p.func
        # foo(x) is a call, but INSERT INTO t (a, b) is a column list.
        return INSERT_LIKE_CLAUSES.include?(top.clause) if p.type == :word || p.type == :quoted_ident

        return true
      end
      return false if t.type == :operator && ["::", "[", "]"].include?(t.text)
      return false if p.type == :operator && (["::", "["].include?(p.text) || @prev_unary)

      true
    end

    def flush_line
      return if @cur.empty?

      @lines << (@indent * @cur_indent + @cur).sub(/[ \t]+\z/, "")
      @cur = +""
    end

    def start_line(level)
      flush_line
      @cur_indent = level
    end

    def blank_line
      flush_line
      @lines << "" unless @lines.empty?
      @cur_indent = 0
    end
  end
end
