# encoding: utf-8

# Wrapper types used by the reader to represent unquote (`~`) and
# unquote-splice (`~@`) forms inside a syntax-quote.
[:Dequote, :Splice].each do |name|
  Rouge.const_set name, Class.new {
    attr_reader :inner

    def initialize(inner)
      @inner = inner
    end

    def self.[](inner)
      new inner
    end

    def inspect
      "#{self.class.name}[#{@inner.inspect}]"
    end

    def ==(right)
      right.is_a?(self.class) and right.inner == @inner
    end
  }
end

# vim: set sw=2 et cc=80:
