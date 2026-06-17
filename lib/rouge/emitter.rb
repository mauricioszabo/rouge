# encoding: utf-8

require 'rouge/ruby_ast'
require 'rouge/env'
require 'set'

module Rouge
  # Walks reader forms and produces a +Rouge::RubyAST+ tree.  Special forms,
  # the core-fn mapping table and the macro engine are mixed in from
  # +special_forms.rb+, +core.rb+ and +macro.rb+ (which reopen this class).
  class Emitter
    include Rouge::RubyAST

    class Error < StandardError; end

    # Namespaces whose qualified calls route through the core mapping table.
    CORE_NS = %w[clojure.core clojure.string clojure.set rouge.core].freeze

    attr_reader :env
    attr_accessor :mode, :loader

    def initialize(env = Rouge::Env.new)
      @env = env
      @mode = :code # :code for ordinary output, :macro inside macro bodies
      @loader = nil
    end

    # Emit a single form as a Ruby *expression* node.
    def emit(form)
      case form
      when Rouge::Seq::Cons, Rouge::Seq::ISeq
        emit_list(form.to_a)
      when ::Array
        ArrayLit.new(form.map { |e| emit(e) })
      when ::Hash
        HashLit.new(form.map { |k, v| [emit(k), emit(v)] })
      when ::Set
        Call.new(ConstPath.new("Set"), "new",
                 [ArrayLit.new(form.map { |e| emit(e) })])
      when Rouge::Symbol
        emit_symbol(form)
      when ::Symbol
        emit_keyword(form)
      when ::String
        StrInterp.new([form])
      when ::Integer
        Lit.new(form.to_s)
      when ::Float
        Lit.new(form.to_s)
      when ::Rational
        Lit.new("Rational(#{form.numerator}, #{form.denominator})")
      when ::Regexp
        Lit.new(form.inspect)
      when true
        Lit.new("true")
      when false
        Lit.new("false")
      when nil
        Lit.new("nil")
      when Rouge::BlockArg
        raise Error, "a ^:block argument can only be spliced into call position"
      else
        raise Error, "can't emit #{form.inspect} (#{form.class})"
      end
    end

    # Emit a sequence of forms as a list of statement nodes, flattening nested
    # +begin+ blocks (from +let+/+do+) into the enclosing body.
    def emit_body(forms)
      nodes = []
      forms.each do |f|
        n = emit(f)
        next if n.nil? # e.g. defmacro emits nothing
        if n.is_a?(Begin)
          nodes.concat(n.body)
        else
          nodes << n
        end
      end
      nodes
    end

    def emit_args(forms)
      forms.map { |f| emit(f) }
    end

    # ---- symbols ----------------------------------------------------------

    def emit_keyword(kw)
      s = kw.to_s
      if s =~ /\A[a-zA-Z_][a-zA-Z0-9_]*[?!]?\z/
        Lit.new(":#{s}")
      else
        Lit.new(":#{s.inspect}")
      end
    end

    def emit_symbol(sym)
      name = sym.name_s

      if (b = @env.lookup_local(sym.to_s))
        return Lit.new(b.ruby_name)
      end

      if sym.ns
        return emit_qualified_value(sym)
      end

      # Bare references.
      return Lit.new("self") if name == "this" || name == "self"
      if name =~ /\A[A-Z]/
        Lit.new(@env.munge_method(name)) # a constant
      else
        Lit.new(@env.munge_var(name))
      end
    end

    # +Foo/BAR+ => +Foo::BAR+ ;  +Foo/bar+ => +Foo.bar+.  A namespace that
    # matches a +:require+ alias resolves to the aliased const path.
    def emit_qualified_value(sym)
      ns = sym.ns_s
      name = sym.name_s
      if name =~ /\A[A-Z]/
        ConstPath.new("#{resolve_ns_path(ns)}::#{name}")
      else
        Call.new(ConstPath.new(resolve_ns_path(ns)), @env.munge_method(name))
      end
    end

    # Resolve a namespace segment to a Ruby const path, honouring require aliases.
    def resolve_ns_path(ns)
      @env.alias_const(ns) || const_path(ns)
    end

    def const_path(ns)
      ns.split(/[.\/]/).map { |p| camelize(p) }.join("::")
    end

    def camelize(part)
      part.split(/[-_]/).map { |w| w.empty? ? "" : w[0].upcase + w[1..] }.join
    end

    # ---- lists ------------------------------------------------------------

    def emit_list(arr)
      return Lit.new("nil") if arr.empty?

      head = arr[0]
      tail = arr[1..]

      unless head.is_a?(Rouge::Symbol)
        # ((f) args) — call the result.
        return Call.new(emit(head), "call", emit_args(tail))
      end

      full = head.to_s
      name = head.name_s

      # Macros expand first (unless shadowed by a local binding).
      if head.ns.nil? && @env.macro?(name) && !@env.local?(full)
        return emit(expand_macro(name, tail))
      end

      # Special forms (only when not shadowed by a local).
      if head.ns.nil? && special_form?(name) && !@env.local?(full)
        return emit_special(name, tail)
      end

      # Inside macro bodies, the form-builder fns map to the runtime that
      # constructs reader data (Cons/Symbol/etc).
      if @mode == :macro && head.ns.nil? && form_fn?(name) && !@env.local?(full)
        return Call.new(ConstPath.new("Rouge::FormRuntime"),
                        @env.munge_method(name), emit_args(tail))
      end

      # Type-dispatched syntaxes (defsyntax / defimpl) win over the core table,
      # so the prelude (or a user) can take over names like +map+ / +reduce+.
      if head.ns.nil? && @env.syntax?(name) && !@env.local?(full)
        return expand_syntax(name, tail)
      end

      # A name brought in unqualified by (:require ... :refer [...]).
      if head.ns.nil? && @env.refer?(name) && !@env.local?(full)
        return emit_refer_call(name, tail)
      end

      # Interop: (.method recv args...)
      if name.start_with?(".") && name.length > 1
        return emit_interop(name[1..], tail)
      end

      # Constructor: (Klass. args...)
      if head.new_sym
        klass = name[0..-2]
        return Call.new(ConstPath.new(const_path_for(head.ns, klass)), "new",
                        emit_args(tail))
      end

      # A require alias resolves before core-ns routing, so the alias is
      # deterministic (e.g. (str/foo) where str is an alias, not clojure.string).
      if head.ns && @env.alias?(head.ns_s)
        return emit_qualified_call(head, tail)
      end

      # Qualified call into a Clojure-ish core namespace maps through the core
      # table (e.g. clojure.string/upper-case).
      if head.ns && CORE_NS.include?(head.ns_s) && core_mapping?(name)
        return emit_core(name, tail)
      end

      # Qualified call: (Foo/bar args) or (other.ns/fn args)
      if head.ns
        return emit_qualified_call(head, tail)
      end

      # Core-fn mapping table.
      if core_mapping?(name) && !@env.local?(full)
        return emit_core(name, tail)
      end

      # Plain call.  A local holding a fn is invoked with .call.
      if (b = @env.lookup_local(full))
        return Call.new(Lit.new(b.ruby_name), "call", emit_args(tail))
      end

      Call.new(nil, @env.munge_method(name), emit_args(tail))
    end

    def const_path_for(ns, name)
      if ns
        "#{const_path(ns)}::#{name}"
      else
        name
      end
    end

    def emit_interop(method, tail)
      recv = emit(tail[0])
      rest = tail[1..]
      block, block_pass, args = extract_block(rest)
      Call.new(recv, @env.munge_method(method), emit_args(args),
               block: block, block_pass: block_pass)
    end

    def emit_qualified_call(head, tail)
      ns = head.ns_s
      name = head.name_s
      block_pass, args = extract_block_pass(tail)
      Call.new(ConstPath.new(resolve_ns_path(ns)), @env.munge_method(name),
               emit_args(args), block_pass: block_pass)
    end

    # A bare name brought in by +:refer+ resolves to a call on its namespace.
    def emit_refer_call(name, tail)
      block_pass, args = extract_block_pass(tail)
      Call.new(ConstPath.new(@env.refer_const(name)), @env.munge_method(name),
               emit_args(args), block_pass: block_pass)
    end

    # Handle a trailing +| f+ marker (Rouge's "pass as block" syntax) inside an
    # interop/call argument list.  Returns [block_pass_node_or_nil, args].
    def extract_block_pass(args)
      idx = args.find_index { |a| a.is_a?(Rouge::Symbol) && a.name_s == "|" }
      return [nil, args] unless idx

      bp = args[idx + 1]
      [emit(bp), args[0...idx]]
    end

    # Pull a block out of an argument list, recognising both a +BlockArg+
    # (spliced by a +defimpl+ +^:block+ param) and the +| f+ marker.  Returns
    # [block_node_or_nil, block_pass_node_or_nil, remaining_arg_forms].
    def extract_block(args)
      bidx = args.find_index { |a| a.is_a?(Rouge::BlockArg) }
      if bidx
        ba = args[bidx]
        block, block_pass = coerce_block(ba.inner, ba.arity)
        return [block, block_pass, args[0...bidx] + args[(bidx + 1)..]]
      end

      pidx = args.find_index { |a| a.is_a?(Rouge::Symbol) && a.name_s == "|" }
      return [nil, emit(args[pidx + 1]), args[0...pidx]] if pidx

      [nil, nil, args]
    end

    # Coerce a function form destined for a Ruby block: a bound local or keyword
    # is passed with +&+, anything else is wrapped in an +arity+-param block
    # (mirrors +seq_op+).  Returns [block_node_or_nil, block_pass_node_or_nil].
    def coerce_block(form, arity)
      # A multi-param block (e.g. mapping over zipped tuples) must destructure,
      # so only pass-through (+&local+ / +&:kw+) when a single param suffices.
      if arity <= 1 && form.is_a?(Rouge::Symbol) && @env.local?(form.to_s)
        [nil, Lit.new(@env.lookup_local(form.to_s).ruby_name)]
      elsif arity <= 1 && form.is_a?(::Symbol)
        [nil, emit_keyword(form)]
      else
        [fn_to_block(form, arity), nil]
      end
    end

    # ---- type hints -------------------------------------------------------

    # The static type we can attribute to a binding symbol, from its metadata.
    def hint_type(sym)
      m = sym.respond_to?(:meta) ? sym.meta : nil
      return nil unless m

      return :map if m[:map]
      return :vector if m[:vector] || m[:vec]
      return :set if m[:set]
      return :string if m[:string] || m[:str]
      return :int if m[:int]
      return :block if m[:block]
      return m[:tag].to_s.to_sym if m[:tag]

      nil
    end

    def block_param?(sym)
      sym.respond_to?(:meta) && sym.meta && sym.meta[:block]
    end

    # Infer a type for a value form (literal or known type-producing call).
    def infer_type(form)
      case form
      when ::Hash then :map
      when ::Array then :vector
      when ::Set then :set
      when ::String then :string
      when ::Integer then :int
      when ::Float then :float
      when true, false then :bool
      when Rouge::Symbol then @env.local_type(form.to_s)
      when Rouge::Seq::Cons, Rouge::Seq::ISeq
        h = form.to_a[0]
        infer_call_type(h)
      end
    end

    def infer_call_type(head)
      return nil unless head.is_a?(Rouge::Symbol) && head.ns.nil?

      case head.name_s
      when "assoc", "dissoc", "merge", "hash-map", "update", "select-keys",
           "zipmap", "assoc-in", "update-in"
        :map
      when "vector", "vec", "mapv", "filterv", "subvec", "into"
        :vector
      when "set", "hash-set", "into-set"
        :set
      when "str", "subs", "name", "join", "trim", "upper-case", "lower-case"
        :string
      end
    end
  end
end

# vim: set sw=2 et cc=80:
