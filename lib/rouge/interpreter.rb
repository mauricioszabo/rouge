# encoding: utf-8

module Rouge
  # Runs Rouge code by *transpiling then evaluating* — there is no separate
  # evaluator, which keeps a single source of truth and means a +defmacro+ is
  # immediately usable by later forms in the same session.  This is the seed
  # for a future nREPL server (which would just delegate eval ops here).
  class Interpreter
    attr_reader :env, :emitter

    def initialize
      @env = Rouge::Env.new
      @emitter = Rouge::Emitter.new(@env)
      # A single persistent top-level binding so defs/classes/locals introduced
      # by earlier forms remain visible to later ones.
      @binding = ::TOPLEVEL_BINDING
    end

    # Read and evaluate every form, returning the value of the last.
    def eval_str(source)
      result = nil
      Rouge::Reader.read_all(source).each { |form| result = eval_form(form) }
      result
    end

    # Transpile a single form and evaluate the resulting Ruby.
    def eval_form(form)
      ruby = transpile_form(form)
      return nil if ruby.empty?

      @binding.eval(ruby)
    end

    # The Ruby a single form transpiles to (handy for a REPL "show emitted
    # Ruby" toggle).
    def transpile_form(form)
      node = @emitter.emit(form)
      node.nil? ? "" : Rouge::PrettyPrinter.print(node)
    end
  end
end

# vim: set sw=2 et cc=80:
