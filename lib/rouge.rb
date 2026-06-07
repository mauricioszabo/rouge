# encoding: utf-8

# Rouge: a Clojure-flavoured language that *transpiles* to readable Ruby.
module Rouge
  require 'set'

  require 'rouge/version'
  require 'rouge/wrappers'
  require 'rouge/metadata'
  require 'rouge/symbol'
  require 'rouge/seq'
  require 'rouge/reader'

  require 'rouge/ruby_ast'
  require 'rouge/pretty_printer'
  require 'rouge/env'
  require 'rouge/form_runtime'
  require 'rouge/emitter'
  require 'rouge/special_forms'
  require 'rouge/core'
  require 'rouge/macro'
  require 'rouge/formatter'
  require 'rouge/transpiler'
  require 'rouge/interpreter'

  # Transpile a string of Rouge source into Ruby source.
  def self.transpile(source, rubocop: false)
    Rouge::Transpiler.transpile(source, rubocop: rubocop)
  end

  # Transpile-then-eval a string of Rouge source, returning the last value.
  def self.eval(source)
    Rouge::Interpreter.new.eval_str(source)
  end
end

# vim: set sw=2 et cc=80:
