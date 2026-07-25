# encoding: utf-8
require 'cursed/wrappers'

class Cursed::Reader
  class UnexpectedCharacterError < StandardError; end
  class NumberFormatError < StandardError; end
  class EndOfDataError < StandardError; end
  class EOFError < StandardError; end

  @@gensym_counter = 0

  def initialize(input)
    @src = input
    @n = 0
    @gensyms = []
  end

  # Read every top-level form from the input.
  def self.read_all(input)
    reader = new(input)
    forms = []
    loop do
      begin
        forms << reader.lex
      rescue EOFError
        break
      end
    end
    forms
  end

  def lex
    case peek
    when MAYBE_NUMBER
      number
    when /:/
      keyword
    when /"/
      string
    when /\(/
      Cursed::Seq::Cons[*list(')')]
    when /\[/
      list ']'
    when /#/
      dispatch
    when SYMBOL
      # SYMBOL after \[ and #, because it includes both
      symbol_or_number
    when /{/
      map
    when /'/
      quotation
    when /`/
      syntaxquotation
    when /~/
      dequotation
    when /\^/
      metadata
    when /@/
      deref
    when nil
      reader_raise EOFError, "in #lex"
    else
      reader_raise UnexpectedCharacterError, "#{peek.inspect} in #lex"
    end
  end

  private

  # Loose expression for a possible numeric literal.
  MAYBE_NUMBER = /^[+\-]?\d[\da-fA-FxX._+\-\/]*/

  # Ruby integer.
  INT = /\d+(?:_\d+)*/

  # Strict expression for a numeric literal.
  NUMBER = /
  [+\-]?
  (?:
    (?:#{INT}(?:(?:\.#{INT})?(?:[eE][+\-]?#{INT})?)?) (?# Integers and floats)
  | (?:0
      (?:
        (?:[xX][\da-fA-F]+) (?# Hexadecimal integer)
      | (?:[bB][01]+) (?# Binary integer)
      | (?:[0-7]+) (?# Octal integer)
      )?
    )
  )
  /ox

  RATIONAL = /#{NUMBER}\/#{NUMBER}/o

  SYMBOL = /
  ^(\.\[\])
  |(\.?[-+]@)
  |([a-zA-Z0-9\-_!&\?\*\/\.\+\|=%$<>#]+)
  /x

  # Advances the current character position by n characters and returns the
  # updated character position.
  def advance! n = 1
    @n += n.abs
  end

  # Retracts the current character position by n characters and returns the
  # updated character position.
  def retract! n = 1
    pos = @n - n.abs

    if pos > 0
      @n = pos
    else
      @n = 0
    end
  end

  # Returns the character currently beneath the cursor.
  def current_char
    @src[@n]
  end

  # Returns the string of characters matching the regular expression re relative
  # to the cursor position. The cursor position is then advanced by n characters
  # where n is the length of the returned string.
  def slurp re
    re.match(@src[@n..-1])

    if $&
      advance!($&.length)
      $&
    else
      reader_raise UnexpectedCharacterError, "#{current_char} in #slurp #{re}"
    end
  end

  # Advances the cursor position beyond whitespace and comments and returns the
  # resulting character.
  def peek
    while /[\s,;]/.match(current_char)
      if $& == ";"
        while /[^\n]/.match(current_char)
          advance!
        end
      else
        advance!
      end
    end

    current_char
  end

  # Returns the result of peek and advances the cursor position by character.
  def consume
    c = peek
    advance!
    c
  end

  # Raises the exception ex with the message msg including line information
  # where the error occured. If the optional string cause is given, a more
  # detailed report will be displayed.
  def reader_raise ex, msg, cause = nil
    # Locate the beginning of the line.
    n = @n
    until n == 0 || @src[n - 1] == "\n"
      n -= 1
    end

    lines = @src[n..-1].lines.to_a
    line = lines.first
    line_no = (@src.lines.to_a.index(line) || 0) + 1

    if cause
      error_position = line.index(cause)
      indicator = (" " * error_position) << ("^" * cause.length)
      info = "on line #{line_no} at char #{error_position}"
      parts = [msg, line.chomp, indicator, info]
    else
      info = "on line #{line_no}"
      parts = [msg, info]
    end

    raise ex, parts.join("\n")
  end

  def number s = slurp(MAYBE_NUMBER)
    if /\A#{NUMBER}\z/o.match(s)
      # Match decimal numbers but not hexadecimal numbers.
      if /[.eE]/.match(s) && /[^xX]/.match(s)
        Float(s)
      else
        Integer(s)
      end
    elsif /\A#{RATIONAL}\z/o.match(s)
      numerator, denominator = s.split("/").map {|n| number(n)}
      Rational(numerator, denominator)
    else
      reader_raise NumberFormatError, "Invalid number #{s}", s
    end
  end

  def keyword
    advance!
    if peek == ?"
      s = string
      s.intern
    else
      slurp(/^[a-zA-Z0-9\-_!\?\*\/]+/).intern
    end
  end

  def string
    s = ""
    t = consume
    while true
      c = current_char

      if c.nil?
        reader_raise EndOfDataError, "in string, got: \"#{s}"
      end

      advance!

      if c == t
        break
      end

      if c == ?\\
        c = consume

        case c
        when nil
          reader_raise EndOfDataError, "in escaped string, got: \"#{s}"
        when /[abefnrstv]/
          c = {
            ?a => ?\a,
            ?b => ?\b,
            ?e => ?\e,
            ?f => ?\f,
            ?n => ?\n,
            ?r => ?\r,
            ?s => ?\s,
            ?t => ?\t,
            ?v => ?\v
          }[c]
        else
          # Just leave it be.
        end
      end

      s << c
    end
    s.freeze
  end

  def list(ending)
    consume
    r = []

    until peek == ending
      r << lex
    end

    consume
    r.freeze
  rescue EOFError
    reader_raise EndOfDataError, "in #list"
  end

  def symbol_or_number
    s = slurp(SYMBOL)

    if MAYBE_NUMBER.match(s)
      number(s)
    else
      Cursed::Symbol[s.intern]
    end
  end

  def map
    consume
    r = {}

    until peek == '}'
      k, v = lex, lex
      r[k] = v
    end

    consume
    r.freeze
  rescue EOFError
    reader_raise EndOfDataError, "in #map"
  end

  def quotation
    consume
    Cursed::Seq::Cons[Cursed::Symbol[:quote], lex]
  rescue EOFError
    reader_raise EndOfDataError, "in #quotation"
  end

  def syntaxquotation
    consume
    @gensyms.unshift(@@gensym_counter += 1)
    r = dequote(lex)
    @gensyms.shift
    r
  rescue EOFError
    reader_raise EndOfDataError, "in #syntaxquotation"
  end

  def dequotation
    consume
    if peek == ?@
      consume
      Cursed::Splice[lex].freeze
    else
      Cursed::Dequote[lex].freeze
    end
  rescue EOFError
    reader_raise EndOfDataError, "in #dequotation"
  end

  def dequote form
    case form
    when Cursed::Seq::ISeq, Array
      rest = []
      group = []
      form.each do |f|
        if f.is_a? Cursed::Splice
          if group.length > 0
            rest << Cursed::Seq::Cons[Cursed::Symbol[:list], *group]
            group = []
          end
          rest << f.inner
        else
          group << dequote(f)
        end
      end

      if group.length > 0
        rest << Cursed::Seq::Cons[Cursed::Symbol[:list], *group]
      end

      r =
        if rest.length == 1
          rest[0]
        else
          Cursed::Seq::Cons[Cursed::Symbol[:concat], *rest]
        end

      if form.is_a?(Array)
        Cursed::Seq::Cons[Cursed::Symbol[:apply],
                    Cursed::Symbol[:vector],
                    r]
      elsif rest.length > 1
        Cursed::Seq::Cons[Cursed::Symbol[:seq], r]
      else
        r
      end
    when Hash
      Hash[form.map {|k,v| [dequote(k), dequote(v)]}]
    when Cursed::Dequote
      form.inner
    when Cursed::Symbol
      if form.ns.nil? and form.name_s =~ /(\#)$/
        Cursed::Seq::Cons[
            Cursed::Symbol[:quote],
            Cursed::Symbol[
                ("#{form.name.to_s.gsub(/(\#)$/, '')}__" \
                 "#{@gensyms[0]}__auto__").intern]]
      else
        # In the transpiler we keep symbols unqualified inside syntax-quote so
        # the emitter can still recognise special forms and core fns.
        Cursed::Seq::Cons[Cursed::Symbol[:quote], form]
      end
    else
      Cursed::Seq::Cons[Cursed::Symbol[:quote], form]
    end
  end

  def regexp
    expression = ""
    terminator = '"'

    while true
      char = current_char

      if char.nil?
        reader_raise EndOfDataError, "in regexp, got: #{expression}"
      end

      advance!

      if char == terminator
        break
      end

      if char == ?\\
        char = "\\"

        # Prevent breaking early.
        if peek == terminator
          char << consume
        end
      end

      expression << char
    end

    Regexp.new(expression).freeze
  end

  def set
    s = Set.new

    until peek == '}'
      s.add(lex)
    end

    consume
    s.freeze
  rescue EOFError
    reader_raise EndOfDataError, "in #set"
  end

  def dispatch
    consume
    case peek
    when '('
      body, count = dispatch_rewrite_fn(lex, 0)
      Cursed::Seq::Cons[
          Cursed::Symbol[:fn],
          (1..count).map {|n| Cursed::Symbol[:"%#{n}"]}.freeze,
          body]
    when "{"
      consume
      set
    when "'"
      consume
      Cursed::Seq::Cons[Cursed::Symbol[:var], lex]
    when "_"
      consume
      lex
      lex
    when '"'
      consume
      regexp
    else
      reader_raise UnexpectedCharacterError, "#{peek.inspect} in #dispatch"
    end
  rescue EOFError
    reader_raise EndOfDataError, "in #dispatch"
  end

  def dispatch_rewrite_fn form, count
    case form
    when Cursed::Seq::Cons, Array
      mapped = form.map do |e|
        e, count = dispatch_rewrite_fn(e, count)
        e
      end.freeze

      if form.is_a?(Cursed::Seq::Cons)
        [Cursed::Seq::Cons[*mapped], count]
      else
        [mapped, count]
      end
    when Cursed::Symbol
      if form.name == :"%"
        [Cursed::Symbol[:"%1"], [1, count].max]
      elsif form.name.to_s =~ /^%(\d+)$/
        [form, [$1.to_i, count].max]
      else
        [form, count]
      end
    else
      [form, count]
    end
  end

  def metadata
    consume
    meta = lex
    attach = lex

    if not attach.class < Cursed::Metadata
      reader_raise ArgumentError,
          "metadata can only be applied to classes mixing in Cursed::Metadata"
    end

    meta =
      case meta
      when Symbol
        {meta => true}
      when String
        {:tag => meta}
      when Cursed::Symbol
        {:tag => meta}
      else
        meta
      end

    extant = attach.meta
    if extant.nil?
      attach.meta = meta
    else
      attach.meta = extant.merge(meta)
    end

    attach
  rescue EOFError
    reader_raise EndOfDataError, "in #meta"
  end

  def deref
    consume
    Cursed::Seq::Cons[Cursed::Symbol[:"cursed.core/deref"], lex]
  rescue EOFError
    reader_raise EndOfDataError, "in #deref"
  end
end

# vim: set sw=2 et cc=80:
