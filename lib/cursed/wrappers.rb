# encoding: utf-8

# Wrapper types used by the reader to represent unquote (`~`) and
# unquote-splice (`~@`) forms inside a syntax-quote.
[:Dequote, :Splice].each do |name|
  Cursed.const_set name, Class.new {
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

# A function argument that a +defimpl+ body splices into the form it builds and
# that the emitter should lower to a Ruby *block* (rather than a positional
# argument).  +arity+ is the number of block parameters to generate when the
# function needs to be wrapped (e.g. +reduce+ wants a 2-ary block).
module Cursed
  class BlockArg
    attr_reader :inner, :arity

    def initialize(inner, arity = 1)
      @inner = inner
      @arity = arity
    end

    def self.[](inner, arity = 1)
      new(inner, arity)
    end

    def inspect
      "BlockArg[#{@inner.inspect}, #{@arity}]"
    end

    def ==(other)
      other.is_a?(self.class) && other.inner == @inner && other.arity == @arity
    end
  end
end

# vim: set sw=2 et cc=80:
