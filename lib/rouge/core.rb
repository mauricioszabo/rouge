# encoding: utf-8

# The clojure.core => Ruby mapping table for the emitter.  Reopens
# +Rouge::Emitter+.  The guiding rules from the design:
#
#  * sequence fns operate on their *last* argument as the Ruby receiver, and a
#    function argument becomes a Ruby block;
#  * collection fns are *type-hint aware* (e.g. +conj+ on a vector vs a map);
#  * arithmetic / comparison lower to Ruby operators.
module Rouge
  class Emitter
    # Function-builder names available inside macro bodies (mapped to
    # +Rouge::FormRuntime+).
    FORM_FNS = %w[list concat seq cons vector gensym symbol].freeze

    def form_fn?(name)
      FORM_FNS.include?(name)
    end

    CORE_NAMES = %w[
      map mapv filter filterv remove keep mapcat reduce each run! doall
      sort sort-by group-by take drop take-while drop-while take-last
      first ffirst second last rest next nth nthrest reverse distinct
      partition partition-all concat into flatten range repeat repeatedly
      some every? not-every? not-any? empty? seq frequencies tally
      min max min-by max-by zipmap map-indexed interpose count keep-indexed
      get get-in assoc dissoc update merge keys vals contains? select-keys
      hash-map conj disj union intersection difference set
      + - * / quot rem mod inc dec = == not= < > <= >= zero? pos? neg?
      even? odd? abs max-of min-of
      str println print prn pr name keyword subs format
      upper-case lower-case trim triml trimr capitalize blank? split join
      replace starts-with? ends-with? includes?
      identity instance? type class deref nil? some? true? false?
      vec to-array boolean
    ].freeze

    CORE_SET = CORE_NAMES.to_h { |n| [n, true] }.freeze

    def core_mapping?(name)
      CORE_SET.key?(name)
    end

    def emit_core(name, tail)
      case name
      # ---- sequence ------------------------------------------------------
      when "map", "mapv"  then emit_map(tail)
      when "filter", "filterv" then seq_op("select", tail[0], tail[1])
      when "remove"       then seq_op("reject", tail[0], tail[1])
      when "keep"         then seq_op("filter_map", tail[0], tail[1])
      when "keep-indexed" then seq_op("each_with_index", tail[0], tail[1])
      when "mapcat"       then seq_op("flat_map", tail[0], tail[1])
      when "map-indexed"  then emit_map_indexed(tail)
      when "reduce"       then emit_reduce(tail)
      when "each", "run!", "doall", "dorun" then seq_op("each", tail[0], tail[1])
      when "sort"         then emit_sort(tail)
      when "sort-by"      then seq_op("sort_by", tail[0], tail[1])
      when "group-by"     then seq_op("group_by", tail[0], tail[1])
      when "min-by"       then seq_op("min_by", tail[0], tail[1])
      when "max-by"       then seq_op("max_by", tail[0], tail[1])
      when "take"         then Call.new(emit(tail[1]), "take", [emit(tail[0])])
      when "take-last"    then Call.new(emit(tail[1]), "last", [emit(tail[0])])
      when "drop"         then Call.new(emit(tail[1]), "drop", [emit(tail[0])])
      when "take-while"   then seq_op("take_while", tail[0], tail[1])
      when "drop-while"   then seq_op("drop_while", tail[0], tail[1])
      when "first"        then Call.new(emit(tail[0]), "first")
      when "second"       then Index.new(emit(tail[0]), [Lit.new("1")])
      when "ffirst"       then Index.new(Call.new(emit(tail[0]), "first"), [Lit.new("0")])
      when "last"         then Call.new(emit(tail[0]), "last")
      when "rest", "next", "nthrest" then Call.new(emit(tail[0]), "drop", [Lit.new("1")])
      when "nth"          then Index.new(emit(tail[0]), [emit(tail[1])])
      when "reverse"      then Call.new(emit(tail[0]), "reverse")
      when "distinct"     then Call.new(emit(tail[0]), "uniq")
      when "flatten"      then Call.new(emit(tail[0]), "flatten")
      when "partition", "partition-all"
        Call.new(Call.new(emit(tail[1]), "each_slice", [emit(tail[0])]), "to_a")
      when "interpose"    then emit_interpose(tail)
      when "concat"       then Binop.new("+", emit_args(tail))
      when "into"         then Binop.new("+", emit_args(tail))
      when "vec", "to-array" then Call.new(emit(tail[0]), "to_a")
      when "range"        then emit_range(tail)
      when "repeat"       then Binop.new("*", [ArrayLit.new([emit(tail[1])]), emit(tail[0])])
      when "some"         then seq_op("find", tail[0], tail[1])
      when "every?"       then seq_op("all?", tail[0], tail[1])
      when "not-every?"   then Unop.new("!", seq_op("all?", tail[0], tail[1]))
      when "not-any?"     then seq_op("none?", tail[0], tail[1])
      when "empty?"       then Call.new(emit(tail[0]), "empty?")
      when "seq", "identity" then emit(tail[0])
      when "frequencies", "tally" then Call.new(emit(tail[0]), "tally")
      when "count"        then Call.new(emit(tail[0]), "size")
      when "zipmap"       then Call.new(Call.new(emit(tail[0]), "zip", [emit(tail[1])]), "to_h")
      when "repeatedly"   then emit_repeatedly(tail)

      # ---- maps / collections -------------------------------------------
      when "get"          then emit_get(tail)
      when "get-in"       then Call.new(emit(tail[0]), "dig",
                                        splat_or_args(tail[1]))
      when "assoc"        then emit_assoc(tail)
      when "dissoc"       then Call.new(emit(tail[0]), "except", emit_args(tail[1..]))
      when "update"       then emit_update(tail)
      when "merge"        then Call.new(emit(tail[0]), "merge", emit_args(tail[1..]))
      when "keys"         then Call.new(emit(tail[0]), "keys")
      when "vals"         then Call.new(emit(tail[0]), "values")
      when "contains?"    then emit_contains(tail)
      when "select-keys"  then Call.new(emit(tail[0]), "slice", splat_or_args(tail[1]))
      when "hash-map"     then emit(pairs_to_hash(tail))
      when "conj"         then emit_conj(tail)
      when "disj"         then Binop.new("-", [emit(tail[0]), ArrayLit.new(emit_args(tail[1..]))])
      when "union"        then Binop.new("|", emit_args(tail))
      when "intersection" then Binop.new("&", emit_args(tail))
      when "difference"   then Binop.new("-", emit_args(tail))
      when "set"          then Call.new(ConstPath.new("Set"), "new", [emit(tail[0])])

      # ---- arithmetic / comparison --------------------------------------
      when "+"            then numeric_op("+", tail, 0)
      when "-"            then numeric_op("-", tail, 0)
      when "*"            then numeric_op("*", tail, 1)
      when "/"            then numeric_op("/", tail, 1)
      when "quot"         then Call.new(emit(tail[0]), "div", [emit(tail[1])])
      when "rem"          then Call.new(emit(tail[0]), "remainder", [emit(tail[1])])
      when "mod"          then Binop.new("%", emit_args(tail))
      when "inc"          then Binop.new("+", [emit(tail[0]), Lit.new("1")])
      when "dec"          then Binop.new("-", [emit(tail[0]), Lit.new("1")])
      when "=", "=="      then compare_op("==", tail)
      when "not="         then Unop.new("!", compare_op("==", tail))
      when "<", ">", "<=", ">=" then compare_op(name, tail)
      when "min"          then Call.new(ArrayLit.new(emit_args(tail)), "min")
      when "max"          then Call.new(ArrayLit.new(emit_args(tail)), "max")
      when "zero?"        then Call.new(emit(tail[0]), "zero?")
      when "pos?"         then Call.new(emit(tail[0]), "positive?")
      when "neg?"         then Call.new(emit(tail[0]), "negative?")
      when "even?"        then Call.new(emit(tail[0]), "even?")
      when "odd?"         then Call.new(emit(tail[0]), "odd?")
      when "abs"          then Call.new(emit(tail[0]), "abs")

      # ---- strings -------------------------------------------------------
      when "str"          then emit_str(tail)
      when "println"      then Call.new(nil, "puts", emit_args(tail))
      when "print"        then Call.new(nil, "print", emit_args(tail))
      when "prn", "pr"    then Call.new(nil, "p", emit_args(tail))
      when "format"       then Call.new(nil, "format", emit_args(tail))
      when "name"         then Call.new(emit(tail[0]), "to_s")
      when "keyword"      then Call.new(emit(tail[0]), "to_sym")
      when "subs"         then emit_subs(tail)
      when "upper-case"   then Call.new(emit(tail[0]), "upcase")
      when "lower-case"   then Call.new(emit(tail[0]), "downcase")
      when "trim"         then Call.new(emit(tail[0]), "strip")
      when "triml"        then Call.new(emit(tail[0]), "lstrip")
      when "trimr"        then Call.new(emit(tail[0]), "rstrip")
      when "capitalize"   then Call.new(emit(tail[0]), "capitalize")
      when "blank?"       then Call.new(Call.new(emit(tail[0]), "to_s"), "strip").then { |s| Call.new(s, "empty?") }
      when "split"        then Call.new(emit(tail[0]), "split", emit_args(tail[1..]))
      when "join"         then emit_join(tail)
      when "replace"      then Call.new(emit(tail[0]), "gsub", emit_args(tail[1..]))
      when "starts-with?" then Call.new(emit(tail[0]), "start_with?", [emit(tail[1])])
      when "ends-with?"   then Call.new(emit(tail[0]), "end_with?", [emit(tail[1])])
      when "includes?"    then Call.new(emit(tail[0]), "include?", [emit(tail[1])])

      # ---- predicates / misc --------------------------------------------
      when "nil?"         then Call.new(emit(tail[0]), "nil?")
      when "some?"        then Unop.new("!", Call.new(emit(tail[0]), "nil?"))
      when "true?"        then Binop.new("==", [emit(tail[0]), Lit.new("true")])
      when "false?"       then Binop.new("==", [emit(tail[0]), Lit.new("false")])
      when "boolean"      then Unop.new("!", Unop.new("!", emit(tail[0])))
      when "instance?"    then Call.new(emit(tail[1]), "is_a?", [emit(tail[0])])
      when "type", "class" then Call.new(emit(tail[0]), "class")
      when "deref"        then emit(tail[0])
      else
        raise Error, "core mapping missing for #{name}"
      end
    end

    # ---- helpers ----------------------------------------------------------

    # A sequence op: receiver is +recv_form+, function arg becomes a block
    # (or +&local+ when it's a bound local).
    def seq_op(method, fn_form, recv_form, extra = [])
      recv = emit(recv_form)
      block = nil
      block_pass = nil
      if fn_form
        if fn_form.is_a?(Rouge::Symbol) && @env.local?(fn_form.to_s)
          block_pass = Lit.new(@env.lookup_local(fn_form.to_s).ruby_name)
        elsif fn_form.is_a?(::Symbol) # a keyword: (map :name coll) -> coll.map(&:name)
          block_pass = emit_keyword(fn_form)
        else
          block = fn_to_block(fn_form)
        end
      end
      Call.new(recv, method, emit_args(extra), block: block, block_pass: block_pass)
    end

    def fn_to_block(form, arity = 1)
      return fn_form_to_block(form) if fn_literal?(form)

      @env.with_scope do
        names = (1..arity).map { @env.gensym("it") }
        names.each { |n| @env.define_local(n) }
        arg_syms = names.map { |n| Rouge::Symbol[n.intern] }
        call = Rouge::Seq::Cons[form, *arg_syms]
        BlockFn.new(names.map { |n| @env.lookup_local(n).ruby_name }, [emit(call)])
      end
    end

    def fn_literal?(form)
      (form.is_a?(Rouge::Seq::Cons) || form.is_a?(Rouge::Seq::ISeq)) &&
        form.to_a[0].is_a?(Rouge::Symbol) &&
        %w[fn fn*].include?(form.to_a[0].name_s)
    end

    def fn_form_to_block(form)
      a = form.to_a[1..]
      a = a[1..] if a[0].is_a?(Rouge::Symbol) # optional name
      return BlockFn.new(["*args"], [Lit.new("nil")]) unless a[0].is_a?(::Array)

      @env.with_scope do
        params, setup = parse_params(a[0])
        BlockFn.new(params, setup + emit_body(a[1..]))
      end
    end

    def emit_map(tail)
      if tail.length > 2
        # (map f c1 c2 ...) -> c1.zip(c2, ...).map { |a, b| f(a, b) }
        colls = tail[1..]
        zipped = Call.new(emit(colls[0]), "zip", emit_args(colls[1..]))
        Call.new(zipped, "map", [], block: fn_to_block(tail[0], colls.length))
      else
        seq_op("map", tail[0], tail[1])
      end
    end

    def emit_map_indexed(tail)
      block = fn_to_block(tail[0], 2)
      # Clojure passes index first; Ruby each_with_index yields value first.
      block = BlockFn.new(block.params.reverse, block.body)
      Call.new(Call.new(emit(tail[1]), "each_with_index"), "map", [], block: block)
    end

    def emit_reduce(tail)
      if tail.length == 3
        Call.new(emit(tail[2]), "inject", [emit(tail[1])], block: fn_to_block(tail[0], 2))
      else
        Call.new(emit(tail[1]), "inject", [], block: fn_to_block(tail[0], 2))
      end
    end

    def emit_sort(tail)
      if tail.length == 1
        Call.new(emit(tail[0]), "sort")
      else
        Call.new(emit(tail[1]), "sort", [], block: fn_to_block(tail[0], 2))
      end
    end

    def emit_range(tail)
      case tail.length
      when 1 then Call.new(Lit.new("(0...#{render_inline(tail[0])})"), "to_a")
      when 2 then Call.new(Lit.new("(#{render_inline(tail[0])}...#{render_inline(tail[1])})"), "to_a")
      else
        Call.new(nil, "Array", [Call.new(Lit.new("(#{render_inline(tail[0])}...#{render_inline(tail[1])})"),
                                          "step", [emit(tail[2])])])
      end
    end

    def emit_repeatedly(tail)
      n = tail.length == 2 ? emit(tail[0]) : emit(tail[0])
      fn = tail.length == 2 ? tail[1] : tail[0]
      Call.new(Call.new(emit(tail[0]), "times"), "map", [], block: fn_to_block(fn, 0))
    end

    def emit_interpose(tail)
      Call.new(Call.new(emit(tail[1]), "flat_map", [],
                        block: BlockFn.new(["x"], [ArrayLit.new([emit(tail[0]), Lit.new("x")])])),
               "drop", [Lit.new("1")])
    end

    def emit_get(tail)
      if tail.length >= 3
        Call.new(emit(tail[0]), "fetch", [emit(tail[1]), emit(tail[2])])
      else
        Index.new(emit(tail[0]), [emit(tail[1])])
      end
    end

    def emit_assoc(tail)
      pairs = tail[1..].each_slice(2).map { |k, v| [emit(k), emit(v)] }
      Call.new(emit(tail[0]), "merge", [HashLit.new(pairs)])
    end

    def emit_update(tail)
      m = tail[0]
      k = tail[1]
      f = tail[2]
      extra = tail[3..]
      cur = Index.new(emit(m), [emit(k)])
      call = Rouge::Seq::Cons[f, Rouge::Symbol[:"__cur"], *extra]
      @env.with_scope do
        @env.define_local("__cur")
        # Bind current value, then apply f.
        applied = apply_fn(f, [Lit.new("__cur")] + emit_args(extra))
        Call.new(emit(m), "merge",
                 [HashLit.new([[emit(k),
                               Begin.new([Assign.new("__cur", cur), applied])]])])
      end
    end

    def apply_fn(f, arg_nodes)
      if f.is_a?(Rouge::Symbol) && core_mapping?(f.name_s) && f.ns.nil?
        # Re-route through core using placeholder lits is hard; fall back to call.
        Call.new(nil, @env.munge_method(f.name_s), arg_nodes)
      elsif f.is_a?(Rouge::Symbol) && @env.local?(f.to_s)
        Call.new(Lit.new(@env.lookup_local(f.to_s).ruby_name), "call", arg_nodes)
      else
        Call.new(nil, @env.munge_method(f.name_s), arg_nodes)
      end
    end

    def emit_contains(tail)
      t = type_of(tail[0])
      method = (t == :vector || t == :set) ? "include?" : "key?"
      Call.new(emit(tail[0]), method, [emit(tail[1])])
    end

    def emit_conj(tail)
      coll = tail[0]
      items = tail[1..]
      t = type_of(coll)
      recv = emit(coll)
      if t == :map
        pairs = items.flat_map do |it|
          if it.is_a?(::Array)
            [[emit(it[0]), emit(it[1])]]
          elsif it.is_a?(::Hash)
            it.map { |k, v| [emit(k), emit(v)] }
          else
            [[emit(it), Lit.new("true")]]
          end
        end
        Call.new(recv, "merge", [HashLit.new(pairs)])
      else
        Binop.new("+", [recv, ArrayLit.new(emit_args(items))])
      end
    end

    def emit_str(tail)
      return StrInterp.new([""]) if tail.empty?

      parts = tail.map { |a| a.is_a?(::String) ? a : emit(a) }
      StrInterp.new(parts)
    end

    def emit_subs(tail)
      if tail.length >= 3
        Index.new(emit(tail[0]),
                  [Lit.new("#{render_inline(tail[1])}...#{render_inline(tail[2])}")])
      else
        Index.new(emit(tail[0]), [Lit.new("#{render_inline(tail[1])}..")])
      end
    end

    def emit_join(tail)
      if tail.length >= 2
        Call.new(emit(tail[1]), "join", [emit(tail[0])])
      else
        Call.new(emit(tail[0]), "join")
      end
    end

    def numeric_op(op, tail, identity)
      return Lit.new(identity.to_s) if tail.empty?
      if tail.length == 1
        return op == "-" ? Unop.new("-", emit(tail[0])) : emit(tail[0])
      end

      Binop.new(op, emit_args(tail))
    end

    def compare_op(op, tail)
      return Lit.new("true") if tail.length < 2

      nodes = emit_args(tail)
      return Binop.new(op, nodes) if nodes.length == 2

      Binop.new("&&", nodes.each_cons(2).map { |a, b| Binop.new(op, [a, b]) })
    end

    def type_of(form)
      t = form.is_a?(Rouge::Symbol) ? hint_type(form) : nil
      t || infer_type(form)
    end

    def pairs_to_hash(tail)
      h = {}
      tail.each_slice(2) { |k, v| h[k] = v }
      h
    end

    def splat_or_args(form)
      if form.is_a?(::Array)
        emit_args(form)
      else
        [Unop.new("*", emit(form))]
      end
    end

    def render_inline(form)
      PrettyPrinter.new.render(emit(form), 0)
    end
  end
end

# vim: set vim: set sw=2 et cc=80:
