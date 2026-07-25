# encoding: utf-8

module Cursed
  # The transpile-time environment.  Tracks:
  #
  #  * lexical scopes, each binding a Clojure name to a munged Ruby name and an
  #    optional *type hint* (used to pick better Ruby for polymorphic core fns);
  #  * the macro registry (name => callable that maps argument forms to a form);
  #  * a gensym counter;
  #  * the current namespace/class context.
  #
  # It also owns name *munging* (Clojure +kebab-case?+ / +bang!+ => Ruby).
  class Env
    Binding = Struct.new(:ruby_name, :type)

    # A type-dispatched syntax (see +syntax.rb+).  +dispatch+ is a callable that
    # maps the call's argument forms to a dispatch token; +impls+ maps a
    # normalized token (+:default+/+:missing+/+:vararg+ or a type symbol) to a
    # list of arity-specific implementations.
    Syntax = Struct.new(:dispatch, :impls)

    # One arity of one +defimpl+.  +callable+ builds a form from the argument
    # forms; +fixed+ is the number of fixed params; +variadic+ is true when it
    # has a +&+ rest; +block_params+ maps a param index to its block arity.
    Impl = Struct.new(:callable, :fixed, :variadic, :block_params)

    attr_accessor :current_ns, :module_ns
    attr_reader :macros, :syntaxes

    def initialize(load_syntaxes: true)
      @scopes = [{}]
      @macros = {}
      @syntaxes = load_syntaxes ? Cursed.default_syntaxes_copy : {}
      @gensym_counter = 0
      @current_ns = nil
      @module_ns = false
      @aliases = {}
      @refers = {}
      @refer_all = []
    end

    # ---- scopes -----------------------------------------------------------

    def push_scope
      @scopes.push({})
    end

    def pop_scope
      @scopes.pop
    end

    def with_scope
      push_scope
      yield
    ensure
      pop_scope
    end

    # Register a local binding, returning its Ruby name.
    def define_local(clj_name, type: nil)
      ruby = munge_var(clj_name)
      @scopes.last[clj_name.to_s] = Binding.new(ruby, type)
      ruby
    end

    def lookup_local(clj_name)
      key = clj_name.to_s
      @scopes.reverse_each do |scope|
        return scope[key] if scope.key?(key)
      end
      nil
    end

    def local?(clj_name)
      !lookup_local(clj_name).nil?
    end

    def local_type(clj_name)
      b = lookup_local(clj_name)
      b && b.type
    end

    # ---- macros -----------------------------------------------------------
    #
    # Macros are scoped to the namespace that defines them (keyed by ns name).
    # An unqualified macro call resolves against the current namespace and any
    # names brought in by +:require ... :refer+; a qualified call resolves
    # against the named (or aliased) namespace.  This mirrors Clojure: a macro
    # is only usable where it was defined or explicitly required.

    DEFAULT_NS = "user".freeze

    def current_ns_key
      @current_ns || DEFAULT_NS
    end

    def define_macro(name, callable)
      (@macros[current_ns_key] ||= {})[name.to_s] = callable
    end

    # Look up a macro callable visible *unqualified* in the current namespace:
    # one defined here, one :refer'd by name, or one from a :refer :all ns.
    def macro(name)
      key = name.to_s
      own = @macros.dig(current_ns_key, key)
      return own if own

      ref_ns = @refers[key]
      return @macros.dig(ref_ns, key) if ref_ns && @macros.dig(ref_ns, key)

      @refer_all.each do |ns|
        found = @macros.dig(ns, key)
        return found if found
      end
      nil
    end

    def macro?(name)
      !macro(name).nil?
    end

    # Look up a macro defined in a specific (already-resolved) namespace.
    def macro_in(ns_name, name)
      @macros.dig(ns_name, name.to_s)
    end

    def macro_in?(ns_name, name)
      !macro_in(ns_name, name).nil?
    end

    # ---- syntaxes ---------------------------------------------------------
    #
    # Like macros, +defsyntax+/+defimpl+ are scoped to their defining namespace
    # and resolved via the current ns, +:refer+/+:refer :all+, then the always
    # visible core namespace (where the prelude's +map+/+reduce+ live, so they
    # behave like +clojure.core+ — referred everywhere automatically).

    # The namespace holding the prelude syntaxes, auto-referred in every ns.
    CORE_SYNTAX_NS = "cursed.core".freeze

    def define_syntax(name, dispatch)
      syn = (ns_syntaxes(current_ns_key)[name.to_s] ||= Syntax.new(nil, {}))
      syn.dispatch = dispatch
    end

    def add_syntax_impl(name, token, impl)
      syn = (ns_syntaxes(current_ns_key)[name.to_s] ||= Syntax.new(nil, {}))
      (syn.impls[token] ||= []) << impl
    end

    # The syntax visible *unqualified* in the current namespace.
    def syntax(name)
      key = name.to_s
      own = @syntaxes.dig(current_ns_key, key)
      return own if own

      ref_ns = @refers[key]
      return @syntaxes.dig(ref_ns, key) if ref_ns && @syntaxes.dig(ref_ns, key)

      @refer_all.each do |ns|
        found = @syntaxes.dig(ns, key)
        return found if found
      end
      @syntaxes.dig(CORE_SYNTAX_NS, key)
    end

    def syntax?(name)
      !syntax(name).nil?
    end

    # A syntax defined in a specific (already-resolved) namespace.
    def syntax_in(ns_name, name)
      @syntaxes.dig(ns_name, name.to_s)
    end

    def syntax_in?(ns_name, name)
      !syntax_in(ns_name, name).nil?
    end

    def ns_syntaxes(ns_name)
      @syntaxes[ns_name] ||= {}
    end

    # ---- require aliases / refers -----------------------------------------
    #
    # Lexical resolution data for the *current* namespace.  +aliases+ maps an
    # alias (e.g. "o") to a namespace name ("other.ns"); +refers+ maps a bare
    # name to the namespace that owns it.  Storing the namespace name (not a
    # Ruby const path) lets the emitter both compute the const path AND resolve
    # referred/qualified macros.  Both tables reset at each +(ns ...)+ boundary
    # so they never leak across files (the compiler reuses one Env project-wide).

    def reset_ns_resolution
      @aliases = {}
      @refers = {}
      @refer_all = []
      @module_ns = false
    end

    # Snapshot/restore the current-namespace resolution state, so loading a
    # dependency mid-namespace doesn't clobber the requiring namespace's aliases.
    def ns_snapshot
      [@aliases.dup, @refers.dup, @refer_all.dup, @module_ns, @current_ns]
    end

    def restore_ns(snap)
      @aliases, @refers, @refer_all, @module_ns, @current_ns = snap
    end

    def define_alias(name, ns_name)
      @aliases[name.to_s] = ns_name
    end

    def alias?(name)
      @aliases.key?(name.to_s)
    end

    def alias_ns(name)
      @aliases[name.to_s]
    end

    def define_refer(name, ns_name)
      @refers[name.to_s] = ns_name
    end

    def refer?(name)
      @refers.key?(name.to_s)
    end

    def refer_ns(name)
      @refers[name.to_s]
    end

    # +:refer :all+ — make every macro in +ns_name+ visible unqualified.
    def define_refer_all(ns_name)
      @refer_all << ns_name unless @refer_all.include?(ns_name)
    end

    # ---- gensym -----------------------------------------------------------

    def gensym(prefix = "g")
      @gensym_counter += 1
      "#{munge_var(prefix)}__#{@gensym_counter}"
    end

    # ---- munging ----------------------------------------------------------

    # Munge a name used as a Ruby *method* (interop and emitted method defs).
    # Ruby method names may keep a trailing +?+ or +!+, which lines up nicely
    # with Clojure predicates / mutators.
    def munge_method(name)
      s = name.to_s
      # Operator methods (+, -, <=>, [], []=, <<, ...) pass through verbatim.
      return s if s =~ %r{\A([-+*/%<>=!&|^~]+|\[\]=?|<<|>>)\z}

      suffix = ""
      if s =~ /([?!])\z/
        suffix = Regexp.last_match(1)
        s = s[0..-2]
      end
      s = s.gsub("->", "_to_")
      s = s.tr("-", "_")
      s = s.gsub(/[^a-zA-Z0-9_]/, "_")
      "#{s}#{suffix}"
    end

    # Munge a name used as a Ruby *local variable* (must be a plain
    # identifier, so +?+/+!+ are spelled out and earmuffs flattened).
    def munge_var(name)
      s = name.to_s
      s = s.sub(/\?\z/, "_p").sub(/!\z/, "_bang")
      s = s.gsub("->", "_to_")
      s = s.tr("-*", "__")
      s = s.gsub(/[^a-zA-Z0-9_]/, "_")
      s = "_#{s}" if s =~ /\A\d/
      s = "_#{s}" if RUBY_KEYWORDS.include?(s)
      s
    end

    RUBY_KEYWORDS = %w[
      begin end def class module if elsif else unless while until for do
      return yield self nil true false and or not then case when in next break
      redo retry rescue ensure super alias undef defined lambda proc
    ].freeze
  end
end

# vim: set sw=2 et cc=80:
