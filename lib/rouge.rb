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
  require 'rouge/syntax'
  require 'rouge/config'
  require 'rouge/ns_form'
  require 'rouge/loader'
  require 'rouge/formatter'
  require 'rouge/transpiler'
  require 'rouge/compiler'
  require 'rouge/interpreter'

  PRELUDE_PATH = File.expand_path('rouge/prelude.clj', __dir__).freeze

  # The syntaxes defined by the prelude, registered once on a throwaway env.
  # Stateless (the impl lambdas resolve the live env at expansion time), so they
  # can be shared across environments.
  def self.default_syntaxes
    @default_syntaxes ||= begin
      env = Rouge::Env.new(load_syntaxes: false)
      em = Rouge::Emitter.new(env)
      Rouge::Reader.read_all(File.read(PRELUDE_PATH)).each { |f| em.emit(f) }
      env.syntaxes
    end
  end

  # A fresh copy of the prelude registry, so per-session +defsyntax+/+defimpl+
  # don't mutate the shared default.
  def self.default_syntaxes_copy
    default_syntaxes.each_with_object({}) do |(name, syn), copy|
      copy[name] = Rouge::Env::Syntax.new(syn.dispatch,
                                          syn.impls.transform_values(&:dup))
    end
  end

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
