# encoding: utf-8

module Rouge
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

    attr_accessor :current_ns
    attr_reader :macros, :syntaxes

    def initialize(load_syntaxes: true)
      @scopes = [{}]
      @macros = {}
      @syntaxes = load_syntaxes ? Rouge.default_syntaxes_copy : {}
      @gensym_counter = 0
      @current_ns = nil
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

    def define_macro(name, callable)
      @macros[name.to_s] = callable
    end

    def macro(name)
      @macros[name.to_s]
    end

    def macro?(name)
      @macros.key?(name.to_s)
    end

    # ---- syntaxes ---------------------------------------------------------

    def define_syntax(name, dispatch)
      syn = (@syntaxes[name.to_s] ||= Syntax.new(nil, {}))
      syn.dispatch = dispatch
    end

    def add_syntax_impl(name, token, impl)
      syn = (@syntaxes[name.to_s] ||= Syntax.new(nil, {}))
      (syn.impls[token] ||= []) << impl
    end

    def syntax(name)
      @syntaxes[name.to_s]
    end

    def syntax?(name)
      @syntaxes.key?(name.to_s)
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
