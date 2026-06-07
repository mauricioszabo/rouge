# encoding: utf-8

# The macro engine.  Reopens +Rouge::Emitter+.
#
# A +defmacro+ transpiles its body (in +:macro+ mode, so syntax-quote /
# +list+ / +concat+ build reader data) into a Ruby lambda, evaluates that
# lambda in-process, and registers it.  At a call site, the lambda is invoked
# with the *unevaluated argument forms* and the returned form is transpiled in
# its place.  Because expansion is plain Ruby, macros can read files, the
# environment, or any data while expanding.
module Rouge
  class Emitter
    def emit_defmacro(tail)
      name_sym = tail[0]
      rest = tail[1..]
      rest = rest[1..] if rest[0].is_a?(::String) # docstring

      lambda_node =
        with_macro_mode do
          if rest[0].is_a?(::Array)
            @env.with_scope do
              params, setup = parse_params(rest[0])
              Lambda.new(params, setup + emit_body(rest[1..]))
            end
          else
            params, body = build_multi_arity(rest)
            Lambda.new(params, body)
          end
        end

      ruby = PrettyPrinter.print(lambda_node)
      callable = TOPLEVEL_BINDING.eval(ruby)
      @env.define_macro(name_sym.name_s, callable)
      nil # macros produce no output in the generated Ruby
    end

    def with_macro_mode
      prev = @mode
      @mode = :macro
      yield
    ensure
      @mode = prev
    end

    # Expand a macro call: invoke the registered lambda with the argument forms.
    def expand_macro(name, arg_forms)
      @env.macro(name).call(*arg_forms)
    end
  end
end

# vim: set sw=2 et cc=80:
