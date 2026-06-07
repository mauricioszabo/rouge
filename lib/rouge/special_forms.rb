# encoding: utf-8

# Special forms for the emitter.  Reopens +Rouge::Emitter+.
module Rouge
  class Emitter
    SPECIAL_FORMS = %w[
      def defn defn- def- defmacro fn fn* let let* if when when-not unless
      cond case do quote var and or not -> ->> when-let if-let throw try
      set! comment declare include extend refine apply new dotimes doseq
    ].freeze

    def special_form?(name)
      SPECIAL_FORMS.include?(name)
    end

    def emit_special(name, tail)
      case name
      when "def"             then emit_def(tail, private: false)
      when "def-"            then emit_def(tail, private: true)
      when "defn"            then emit_defn(tail, private: false)
      when "defn-"           then emit_defn(tail, private: true)
      when "defmacro"        then emit_defmacro(tail)
      when "fn", "fn*"       then emit_fn(tail)
      when "let", "let*"     then emit_let(tail)
      when "if"              then emit_if(tail)
      when "when"            then emit_when(tail, negate: false)
      when "when-not", "unless" then emit_when(tail, negate: true)
      when "cond"            then emit_cond(tail)
      when "case"            then emit_case(tail)
      when "do"              then Begin.new(emit_body(tail))
      when "quote"           then emit_quote(tail[0])
      when "var"             then emit(tail[0])
      when "and"             then emit_andor("&&", tail)
      when "or"              then emit_andor("||", tail)
      when "not"             then Unop.new("!", emit(tail[0]))
      when "->"              then emit(thread_first(tail))
      when "->>"             then emit(thread_last(tail))
      when "when-let"        then emit_when_let(tail)
      when "if-let"          then emit_if_let(tail)
      when "throw"           then Call.new(nil, "raise", emit_args(tail))
      when "try"             then emit_try(tail)
      when "set!"            then emit_set(tail)
      when "comment", "declare" then Lit.new("nil")
      when "include", "extend"  then emit_mixin(name, tail)
      when "refine"          then emit_refine(tail)
      when "apply"           then emit_apply(tail)
      when "new"             then emit_new(tail)
      when "dotimes"         then emit_dotimes(tail)
      when "doseq"           then emit_doseq(tail)
      else
        raise Error, "unhandled special form #{name}"
      end
    end

    # ---- def / defn -------------------------------------------------------

    def emit_def(tail, private:)
      name_sym = tail[0]
      rest = tail[1..]
      rest = rest[1..] if rest[0].is_a?(::String) # docstring
      value = rest[0]
      body = value.nil? ? [Lit.new("nil")] : [emit(value)]
      MethodDef.new(@env.munge_method(name_sym.name_s), [], body,
                    visibility: private ? :private : nil)
    end

    def emit_defn(tail, private:)
      name_sym = tail[0]
      rest = tail[1..]
      rest = rest[1..] if rest[0].is_a?(::String)         # docstring
      rest = rest[1..] if rest[0].is_a?(::Hash)           # attr-map

      meta = name_sym.respond_to?(:meta) ? (name_sym.meta || {}) : {}
      singleton = !!(meta[:self] || meta[:class] || meta[:static])
      visibility = (private || meta[:private]) ? :private : nil
      mname = @env.munge_method(name_sym.name_s)

      if rest[0].is_a?(::Array)
        params, body = build_arity(rest[0], rest[1..])
        MethodDef.new(mname, params, body,
                      singleton: singleton, visibility: visibility)
      else
        # Multi-arity: each element is (params body...).
        params, body = build_multi_arity(rest)
        MethodDef.new(mname, params, body,
                      singleton: singleton, visibility: visibility)
      end
    end

    # Build a single arity: returns [params, body_nodes].
    def build_arity(arg_vec, body_forms)
      @env.with_scope do
        params, setup = parse_params(arg_vec)
        [params, setup + emit_body(body_forms)]
      end
    end

    # Build a *args method that dispatches on argument count.
    def build_multi_arity(arities)
      clauses = []
      arities.each do |arity|
        a = arity.to_a
        arg_vec = a[0]
        body_forms = a[1..]
        @env.with_scope do
          params, setup = parse_params(arg_vec)
          binders = bind_from_args(params)
          clauses << [arg_vec.to_a.length, binders + setup + emit_body(body_forms)]
        end
      end
      cnode = Case.new(Lit.new("args.length"),
                       clauses.map { |n, body| [Lit.new(n.to_s), body] })
      [["*args"], [cnode]]
    end

    # For multi-arity, destructure +args+ into the declared param names.
    def bind_from_args(params)
      return [] if params.empty?

      targets = params.map { |p| p.sub(/\A[*&]/, "") }
      [Assign.new(targets.join(", "), Lit.new("args"))]
    end

    # ---- fn ---------------------------------------------------------------

    def emit_fn(tail)
      tail = tail[1..] if tail[0].is_a?(Rouge::Symbol) # optional name
      if tail[0].is_a?(::Array)
        @env.with_scope do
          params, setup = parse_params(tail[0])
          Lambda.new(params, setup + emit_body(tail[1..]))
        end
      else
        params, body = build_multi_arity(tail)
        Lambda.new(params, body)
      end
    end

    # ---- let --------------------------------------------------------------

    def emit_let(tail)
      bindings = tail[0].to_a
      body = tail[1..]
      @env.with_scope do
        nodes = []
        bindings.each_slice(2) do |sym, valform|
          nodes.concat(emit_binding(sym, valform))
        end
        nodes.concat(emit_body(body))
        Begin.new(nodes)
      end
    end

    def emit_binding(sym, valform)
      type = nil
      type = hint_type(sym) if sym.is_a?(Rouge::Symbol)
      type ||= infer_type(valform)
      value = emit(valform)

      case sym
      when ::Array
        names = sym.map { |s| @env.define_local(s) }
        [Assign.new(names.join(", "), value)]
      when ::Hash
        g = @env.gensym("m")
        [Assign.new(g, value)] + destructure_map(sym, Lit.new(g))
      else
        ruby = @env.define_local(sym, type: type)
        [Assign.new(ruby, value)]
      end
    end

    # ---- conditionals -----------------------------------------------------

    def emit_if(tail)
      cond, then_f, else_f = tail[0], tail[1], tail[2]
      tnode = emit(then_f)
      enode = tail.length > 2 ? emit(else_f) : Lit.new("nil")

      if statement_node?(tnode) || statement_node?(enode)
        clauses = [[emit(cond), body_of(tnode)]]
        If.new(clauses, tail.length > 2 ? body_of(enode) : nil)
      else
        Ternary.new(emit(cond), tnode, enode)
      end
    end

    def emit_when(tail, negate:)
      cond = emit(tail[0])
      cond = Unop.new("!", cond) if negate
      If.new([[cond, emit_body(tail[1..])]])
    end

    def emit_cond(tail)
      clauses = []
      else_body = nil
      tail.each_slice(2) do |test, expr|
        if test.is_a?(::Symbol) && test == :else
          else_body = body_of(emit(expr))
        elsif test.is_a?(Rouge::Symbol) && test.name_s == "else"
          else_body = body_of(emit(expr))
        else
          clauses << [emit(test), body_of(emit(expr))]
        end
      end
      If.new(clauses, else_body)
    end

    def emit_case(tail)
      subject = emit(tail[0])
      rest = tail[1..]
      else_body = nil
      if rest.length.odd?
        else_body = body_of(emit(rest[-1]))
        rest = rest[0...-1]
      end
      clauses = []
      rest.each_slice(2) do |test, expr|
        clauses << [emit(test), body_of(emit(expr))]
      end
      Case.new(subject, clauses, else_body)
    end

    def emit_andor(op, tail)
      return Lit.new(op == "&&" ? "true" : "nil") if tail.empty?
      return emit(tail[0]) if tail.length == 1

      Binop.new(op, emit_args(tail))
    end

    def emit_when_let(tail)
      binding = tail[0].to_a
      sym, valform = binding[0], binding[1]
      @env.with_scope do
        ruby = @env.define_local(sym)
        If.new([[Assign.new(ruby, emit(valform)), emit_body(tail[1..])]])
      end
    end

    def emit_if_let(tail)
      binding = tail[0].to_a
      sym, valform = binding[0], binding[1]
      then_f = tail[1]
      else_f = tail[2]
      @env.with_scope do
        ruby = @env.define_local(sym)
        cond = Assign.new(ruby, emit(valform))
        tnode = emit(then_f)
        enode = tail.length > 2 ? emit(else_f) : Lit.new("nil")
        If.new([[cond, body_of(tnode)]], tail.length > 2 ? body_of(enode) : nil)
      end
    end

    # ---- misc -------------------------------------------------------------

    def emit_try(tail)
      body = []
      rescues = []
      ensure_body = nil
      tail.each do |form|
        if form.is_a?(Rouge::Seq::Cons) || form.is_a?(Rouge::Seq::ISeq)
          a = form.to_a
          head = a[0]
          if head.is_a?(Rouge::Symbol) && head.name_s == "catch"
            klass = emit(a[1])
            var = @env.with_scope { @env.define_local(a[2]) }
            @env.with_scope do
              @env.define_local(a[2])
              rescues << [klass, @env.lookup_local(a[2].to_s).ruby_name,
                          emit_body(a[3..])]
            end
            next
          elsif head.is_a?(Rouge::Symbol) && head.name_s == "finally"
            ensure_body = emit_body(a[1..])
            next
          end
        end
        body << emit(form)
      end
      TryCatch.new(body, rescues, ensure_body)
    end

    def emit_set(tail)
      target = tail[0]
      value = emit(tail[1])
      if (target.is_a?(Rouge::Seq::Cons) || target.is_a?(Rouge::Seq::ISeq))
        a = target.to_a
        if a[0].is_a?(Rouge::Symbol) && a[0].name_s.start_with?(".")
          field = a[0].name_s[1..]
          return Call.new(emit(a[1]), "#{@env.munge_method(field)}=", [value])
        end
      end
      Assign.new(emit(target).str, value)
    end

    def emit_mixin(name, tail)
      mods = tail.map { |t| render_const(t) }.join(", ")
      Lit.new("#{name} #{mods}")
    end

    def render_const(form)
      PrettyPrinter.new.render(emit(form), 0)
    end

    def emit_refine(tail)
      klass = emit(tail[0])
      block = BlockFn.new([], emit_body(tail[1..]))
      Call.new(nil, "refine", [klass], block: block)
    end

    def emit_apply(tail)
      f = tail[0]
      mid = tail[1..-2] || []
      last = tail[-1]
      args = emit_args(mid)
      args << Unop.new("*", emit(last)) if tail.length > 1

      if @mode == :macro && f.is_a?(Rouge::Symbol) && form_fn?(f.name_s)
        return Call.new(ConstPath.new("Rouge::FormRuntime"),
                        @env.munge_method(f.name_s), args)
      end

      if f.is_a?(Rouge::Symbol) && !@env.local?(f.to_s) && f.ns.nil?
        Call.new(nil, @env.munge_method(f.name_s), args)
      else
        Call.new(emit(f), "call", args)
      end
    end

    def emit_new(tail)
      Call.new(emit(tail[0]), "new", emit_args(tail[1..]))
    end

    def emit_dotimes(tail)
      binding = tail[0].to_a
      sym, n = binding[0], binding[1]
      @env.with_scope do
        ruby = @env.define_local(sym, type: :int)
        block = BlockFn.new([ruby], emit_body(tail[1..]))
        Call.new(emit(n), "times", [], block: block)
      end
    end

    def emit_doseq(tail)
      binding = tail[0].to_a
      sym, coll = binding[0], binding[1]
      @env.with_scope do
        ruby = @env.define_local(sym)
        block = BlockFn.new([ruby], emit_body(tail[1..]))
        Call.new(emit(coll), "each", [], block: block)
      end
    end

    # ---- threading --------------------------------------------------------

    def thread_first(tail)
      thread(tail, first: true)
    end

    def thread_last(tail)
      thread(tail, first: false)
    end

    def thread(tail, first:)
      acc = tail[0]
      tail[1..].each do |step|
        acc =
          if step.is_a?(Rouge::Seq::Cons) || step.is_a?(Rouge::Seq::ISeq)
            a = step.to_a
            if first
              Rouge::Seq::Cons[a[0], acc, *a[1..]]
            else
              Rouge::Seq::Cons[*a, acc]
            end
          else
            Rouge::Seq::Cons[step, acc]
          end
      end
      acc
    end

    # ---- quote ------------------------------------------------------------

    def emit_quote(form)
      if @mode == :macro
        quote_data(form)
      else
        quote_code(form)
      end
    end

    # Quote producing plain Ruby data (used in ordinary code).
    def quote_code(form)
      case form
      when Rouge::Symbol then Lit.new(":#{form.name_s}")
      when ::Symbol then emit_keyword(form)
      when Rouge::Seq::Cons, Rouge::Seq::ISeq
        ArrayLit.new(form.to_a.map { |f| quote_code(f) })
      when ::Array then ArrayLit.new(form.map { |f| quote_code(f) })
      when ::Hash then HashLit.new(form.map { |k, v| [quote_code(k), quote_code(v)] })
      else emit(form)
      end
    end

    # Quote producing reader-form data (used inside macro bodies).
    def quote_data(form)
      case form
      when Rouge::Symbol then Lit.new("Rouge::Symbol[#{form.to_sym.inspect}]")
      when ::Symbol then Lit.new(form.inspect)
      when Rouge::Seq::Cons, Rouge::Seq::ISeq
        Index.new(ConstPath.new("Rouge::Seq::Cons"),
                  form.to_a.map { |f| quote_data(f) })
      when ::Array then ArrayLit.new(form.map { |f| quote_data(f) })
      when ::Hash then HashLit.new(form.map { |k, v| [quote_data(k), quote_data(v)] })
      else emit(form)
      end
    end

    # ---- helpers ----------------------------------------------------------

    def statement_node?(node)
      node.is_a?(If) || node.is_a?(Case) || node.is_a?(Begin) ||
        node.is_a?(MethodDef) || node.is_a?(ClassDef) ||
        node.is_a?(ModuleDef) || node.is_a?(TryCatch)
    end

    def body_of(node)
      node.is_a?(Begin) ? node.body : [node]
    end

    # Parse an argument vector into [param_strings, setup_nodes], registering
    # locals (with type hints) in the current scope.
    def parse_params(vec)
      params = []
      setup = []
      arr = vec.to_a
      i = 0
      while i < arr.length
        p = arr[i]
        if p.is_a?(Rouge::Symbol) && p.name_s == "&"
          rest = arr[i + 1]
          params << "*#{@env.define_local(rest, type: :vector)}"
          i += 2
          next
        end
        if p.is_a?(Rouge::Symbol) && block_param?(p)
          params << "&#{@env.define_local(p, type: :block)}"
          i += 1
          next
        end
        case p
        when Rouge::Symbol
          params << @env.define_local(p, type: hint_type(p))
        when ::Array
          names = p.map { |s| @env.define_local(s, type: hint_type(s)) }
          params << "(#{names.join(', ')})"
        when ::Hash
          g = @env.gensym("opts")
          params << g
          setup.concat(destructure_map(p, Lit.new(g)))
        end
        i += 1
      end
      [params, setup]
    end

    def destructure_map(map, src_node)
      nodes = []
      map.each do |k, v|
        key = k.is_a?(Rouge::Symbol) ? k.name : k
        if key == :keys
          v.each do |s|
            r = @env.define_local(s)
            nodes << Assign.new(r, Index.new(src_node, [emit_keyword(s.name)]))
          end
        elsif key == :as
          r = @env.define_local(v)
          nodes << Assign.new(r, src_node)
        else
          r = @env.define_local(k)
          nodes << Assign.new(r, Index.new(src_node, [emit(v)]))
        end
      end
      nodes
    end
  end
end

# vim: set sw=2 et cc=80:
