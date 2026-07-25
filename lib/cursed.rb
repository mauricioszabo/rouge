# encoding: utf-8

# Cursed: a Clojure-flavoured language that *transpiles* to readable Ruby.
module Cursed
  require 'set'

  require 'cursed/version'
  require 'cursed/wrappers'
  require 'cursed/metadata'
  require 'cursed/symbol'
  require 'cursed/seq'
  require 'cursed/reader'

  require 'cursed/ruby_ast'
  require 'cursed/pretty_printer'
  require 'cursed/env'
  require 'cursed/form_runtime'
  require 'cursed/emitter'
  require 'cursed/special_forms'
  require 'cursed/core'
  require 'cursed/macro'
  require 'cursed/syntax'
  require 'cursed/config'
  require 'cursed/ns_form'
  require 'cursed/loader'
  require 'cursed/formatter'
  require 'cursed/transpiler'
  require 'cursed/compiler'
  require 'cursed/interpreter'

  PRELUDE_PATH = File.expand_path('cursed/prelude.clj', __dir__).freeze

  # The syntaxes defined by the prelude, registered once on a throwaway env into
  # the core namespace.  Stateless (the impl lambdas resolve the live env at
  # expansion time), so they can be shared across environments.  Shape:
  # { "cursed.core" => { name => Syntax } }.
  def self.default_syntaxes
    @default_syntaxes ||= begin
      env = Cursed::Env.new(load_syntaxes: false)
      env.current_ns = Cursed::Env::CORE_SYNTAX_NS
      em = Cursed::Emitter.new(env)
      Cursed::Reader.read_all(File.read(PRELUDE_PATH)).each { |f| em.emit(f) }
      env.syntaxes
    end
  end

  # A fresh (deep) copy of the prelude registry, so per-session
  # +defsyntax+/+defimpl+ don't mutate the shared default.
  def self.default_syntaxes_copy
    default_syntaxes.each_with_object({}) do |(ns, by_name), copy|
      copy[ns] = by_name.each_with_object({}) do |(name, syn), inner|
        inner[name] = Cursed::Env::Syntax.new(syn.dispatch,
                                             syn.impls.transform_values(&:dup))
      end
    end
  end

  # Transpile a string of Cursed source into Ruby source.
  def self.transpile(source, rubocop: false)
    Cursed::Transpiler.transpile(source, rubocop: rubocop)
  end

  # Transpile-then-eval a string of Cursed source, returning the last value.
  def self.eval(source)
    Cursed::Interpreter.new.eval_str(source)
  end
end

# vim: set sw=2 et cc=80:
