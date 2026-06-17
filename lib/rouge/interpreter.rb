# encoding: utf-8

module Rouge
  # Runs Rouge code by *transpiling then evaluating* — there is no separate
  # evaluator, which keeps a single source of truth and means a +defmacro+ is
  # immediately usable by later forms in the same session.  Backs the REPL and
  # the nREPL server.
  #
  # Namespace-aware: an +(ns ...)+ form opens a namespace (loading its
  # +:require+ dependencies *live* into the session via a +:dev+ Loader), and
  # subsequent top-level definitions are evaluated *into* that namespace (the
  # module/class is reopened), so the interactive experience matches the AOT
  # output.
  class Interpreter
    DEF_FORMS = %w[def defn def- defn-].freeze

    attr_reader :env, :emitter, :loader

    def initialize(config: nil)
      @env = Rouge::Env.new
      @config = config || Rouge::Config.load
      @transpiler = Rouge::Transpiler.new(@env, config: @config, mode: :dev)
      @emitter = @transpiler.emitter
      @loader = @transpiler.loader
      @loader.load_rouge_source = ->(path) { eval_str(File.read(path)) }
      @current_ns_form = nil
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
      if ns_form?(form)
        eval_ns(form)
      elsif @current_ns_form && def_form?(form)
        eval_ruby(@transpiler.transpile_forms([@current_ns_form, form]))
      else
        ruby = transpile_form(form)
        ruby.empty? ? nil : eval_ruby(ruby)
      end
    end

    # The Ruby a single form transpiles to (handy for a REPL "show emitted
    # Ruby" toggle).
    def transpile_form(form)
      node = @emitter.emit(form)
      node.nil? ? "" : Rouge::PrettyPrinter.print(node)
    end

    private

    # Open a namespace: load its requires live and define the (empty) module/
    # class, then remember the ns form so later defs reopen it.
    def eval_ns(form)
      eval_ruby(@transpiler.transpile_forms([form]))
      @current_ns_form = form
      nil
    end

    def eval_ruby(ruby)
      return nil if ruby.empty?

      @binding.eval(ruby)
    end

    def ns_form?(form)
      list?(form) && form.to_a[0].is_a?(Rouge::Symbol) && form.to_a[0].name_s == "ns"
    end

    def def_form?(form)
      list?(form) && form.to_a[0].is_a?(Rouge::Symbol) &&
        DEF_FORMS.include?(form.to_a[0].name_s)
    end

    def list?(form)
      form.is_a?(Rouge::Seq::Cons) || form.is_a?(Rouge::Seq::ISeq)
    end
  end
end

# vim: set sw=2 et cc=80:
