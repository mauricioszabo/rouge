# encoding: utf-8

# The type-dispatched syntax engine (+defsyntax+ / +defimpl+).  Reopens
# +Rouge::Emitter+.
#
# A +defsyntax+ registers a *dispatch fn* (a defmacro-style lambda over the
# argument forms) that returns a dispatch token.  A +defimpl+ registers, per
# token, a defmacro-style body that builds the form to emit in the call's place.
# At a call site the emitter runs the dispatch fn, picks the matching impl
# (falling back +exact -> :default -> :missing -> :vararg+, by arity) and
# transpiles the form the impl returns.
#
# A +^:block+ (or +^{:block N}+) impl param is spliced as a Ruby block: its
# argument form is wrapped in a +Rouge::BlockArg+ before the impl runs, which the
# emitter then lowers via +coerce_block+.
module Rouge
  class Emitter
    # Map class-name / built-in tokens onto the canonical symbols +type_of+
    # produces, so +(defimpl map Array ...)+ matches a vector literal, etc.
    TOKEN_ALIASES = {
      "array" => :vector, "vector" => :vector,
      "hash" => :map, "map" => :map,
      "set" => :set,
      "string" => :string, "str" => :string,
      "integer" => :int, "int" => :int,
      "float" => :float,
      "bool" => :bool, "boolean" => :bool
    }.freeze

    def emit_defsyntax(tail)
      name = tail[0].name_s
      dispatch_form = tail[1]
      lambda_node = with_macro_mode { emit(dispatch_form) }
      callable = TOPLEVEL_BINDING.eval(PrettyPrinter.print(lambda_node))
      @env.define_syntax(name, callable)
      nil
    end

    def emit_defimpl(tail)
      name = tail[0].name_s
      token = normalize_token(token_string(tail[1]))
      rest = tail[2..]
      arities = rest[0].is_a?(::Array) ? [rest] : rest.map(&:to_a)

      arities.each do |arity|
        params_vec = arity[0]
        body = arity[1..]
        fixed, variadic = arity_of(params_vec)
        block_params = nil
        lambda_node =
          with_macro_mode do
            @env.with_scope do
              params, block_params = parse_impl_params(params_vec)
              Lambda.new(params, emit_body(body))
            end
          end
        callable = TOPLEVEL_BINDING.eval(PrettyPrinter.print(lambda_node))
        @env.add_syntax_impl(name, token,
                             Env::Impl.new(callable, fixed, variadic,
                                           block_params))
      end
      nil
    end

    # Expand a syntax call: resolve the impl, wrap +^:block+ args, run the impl
    # and transpile the form it returns.
    def expand_syntax(name, arg_forms, via_apply: false)
      do_expand_syntax(@env.syntax(name), name, arg_forms, via_apply)
    end

    # Expand a syntax resolved to a specific namespace (qualified/aliased call).
    def expand_syntax_in(ns_name, name, arg_forms, via_apply: false)
      do_expand_syntax(@env.syntax_in(ns_name, name), name, arg_forms, via_apply)
    end

    def do_expand_syntax(syn, name, arg_forms, via_apply)
      impl, = resolve_impl(syn, name, arg_forms, via_apply)
      wrapped = wrap_block_args(arg_forms, impl)
      result = with_syntax_emitter { impl.callable.call(*wrapped) }
      emit(result)
    end

    # ---- resolution -------------------------------------------------------

    def resolve_impl(syn, name, arg_forms, via_apply)
      argc = arg_forms.length

      if via_apply
        impl = pick_arity(syn.impls[:vararg], argc)
        return [impl, :vararg] if impl

        raise Error, "apply: syntax '#{name}' has no :vararg impl"
      end

      dv = dispatch_value(syn, arg_forms)
      token = dv && normalize_token(dv.to_s)

      if token && (impl = pick_arity(syn.impls[token], argc))
        return [impl, token]
      end
      if (impl = pick_arity(syn.impls[:default], argc))
        return [impl, :default]
      end
      if (impl = pick_arity(syn.impls[:missing], argc))
        warn "rouge: #{name}: unresolved dispatch type #{dv.inspect}; " \
             "using :missing impl"
        return [impl, :missing]
      end
      if (impl = pick_arity(syn.impls[:vararg], argc))
        return [impl, :vararg]
      end

      raise Error,
            "no matching impl for (#{name} ...) [#{argc} args, " \
            "dispatch=#{dv.inspect}]"
    end

    def dispatch_value(syn, arg_forms)
      return nil unless syn.dispatch

      with_syntax_emitter { syn.dispatch.call(*arg_forms) }
    rescue StandardError
      # A dispatch fn whose arity doesn't fit the call (e.g. a 2-ary fn on a
      # variadic call) just means "type unknown" -> fall through.
      nil
    end

    def pick_arity(impls, argc)
      return nil unless impls

      impls.find { |im| im.variadic ? argc >= im.fixed : im.fixed == argc }
    end

    # ---- helpers ----------------------------------------------------------

    # Make +type-of+ (and any future introspection) inside a dispatch fn / impl
    # resolve against this live emitter.
    def with_syntax_emitter
      prev = Rouge::FormRuntime.emitter
      Rouge::FormRuntime.emitter = self
      yield
    ensure
      Rouge::FormRuntime.emitter = prev
    end

    def wrap_block_args(arg_forms, impl)
      return arg_forms if impl.block_params.empty?

      args = arg_forms.dup
      impl.block_params.each do |idx, arity|
        args[idx] = Rouge::BlockArg[args[idx], arity] if idx < args.length
      end
      args
    end

    def token_string(form)
      form.is_a?(Rouge::Symbol) ? form.name_s : form.to_s
    end

    def normalize_token(str)
      s = str.to_s
      TOKEN_ALIASES[s.downcase] || s.to_sym
    end

    def arity_of(vec)
      arr = vec.to_a
      amp = arr.find_index { |p| p.is_a?(Rouge::Symbol) && p.name_s == "&" }
      amp ? [amp, true] : [arr.length, false]
    end

    # Parse impl params, treating +^:block+ as an ordinary (form-receiving)
    # param while recording its index/arity.  Returns [param_strings,
    # block_params_hash].
    def parse_impl_params(vec)
      params = []
      block_params = {}
      arr = vec.to_a
      i = 0
      idx = 0
      while i < arr.length
        p = arr[i]
        if p.is_a?(Rouge::Symbol) && p.name_s == "&"
          rest = arr[i + 1]
          params << "*#{@env.define_local(rest, type: :vector)}"
          i += 2
          idx += 1
          next
        end
        if p.is_a?(Rouge::Symbol) && block_param?(p)
          block_params[idx] = p.meta[:block].is_a?(::Integer) ? p.meta[:block] : 1
          params << @env.define_local(p)
        else
          params << @env.define_local(p, type: hint_type(p))
        end
        i += 1
        idx += 1
      end
      [params, block_params]
    end
  end
end

# vim: set sw=2 et cc=80:
