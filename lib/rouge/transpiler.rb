# encoding: utf-8

module Rouge
  # Orchestrates the pipeline: read forms, expand macros + emit Ruby IR, pretty
  # print, optionally run Rubocop.  Top-level +(ns ...)+ forms open a class (the
  # following top-level forms become its body).
  class Transpiler
    include Rouge::RubyAST

    def self.transpile(source, rubocop: false)
      new.transpile(source, rubocop: rubocop)
    end

    attr_reader :env, :emitter, :config, :loader

    def initialize(env = Rouge::Env.new, config: nil, mode: :compile)
      @env = env
      @emitter = Rouge::Emitter.new(@env)
      @config = config || Rouge::Config.new(Dir.pwd, {})
      @mode = mode
      @loader = Rouge::Loader.new(@config, mode: @mode, env: @env)
      @loader.load_rouge_source = method(:macro_load_file)
      @emitter.loader = @loader
    end

    def transpile(source, rubocop: false)
      ruby = Rouge::PrettyPrinter.print_all(process_forms(Rouge::Reader.read_all(source)))
      rubocop ? Rouge::Formatter.rubocop(ruby) : ruby
    end

    # Public: turn a list of already-read forms into Ruby (used by the Compiler).
    def transpile_forms(forms, rubocop: false)
      ruby = Rouge::PrettyPrinter.print_all(process_forms(forms))
      rubocop ? Rouge::Formatter.rubocop(ruby) : ruby
    end

    # Compile-mode dependency load: run a dep's forms through the shared emitter
    # so its macros/syntaxes register, discarding the emitted output (the dep is
    # compiled to its own file).
    def macro_load_file(path)
      process_forms(Rouge::Reader.read_all(File.read(path)))
      nil
    end

    private

    def process_forms(forms)
      top = []
      i = 0
      while i < forms.length
        form = forms[i]
        if ns_form?(form)
          j = i + 1
          body_forms = []
          while j < forms.length && !ns_form?(forms[j])
            body_forms << forms[j]
            j += 1
          end
          top.concat(build_namespace(form, body_forms))
          i = j
        else
          node = @emitter.emit(form)
          top << node unless node.nil?
          i += 1
        end
      end
      top
    end

    def ns_form?(form)
      list?(form) && form.to_a[0].is_a?(Rouge::Symbol) && form.to_a[0].name_s == "ns"
    end

    def list?(form)
      form.is_a?(Rouge::Seq::Cons) || form.is_a?(Rouge::Seq::ISeq)
    end

    def build_namespace(ns_form, body_forms)
      nsf = Rouge::NsForm.parse(ns_form)
      name_sym = nsf.name_sym
      meta = nsf.meta

      @env.current_ns = nsf.name
      @env.reset_ns_resolution
      @env.module_ns = nsf.module?

      require_nodes = process_requires(nsf)

      parts = name_sym.name_parts.map { |p| @emitter.camelize(p.to_s) }
      superclass = meta[:extends] ? const_name(meta[:extends]) : nil

      body_nodes = []
      mixins(meta[:include]).each { |m| body_nodes << Lit.new("include #{m}") }
      mixins(meta[:extend]).each  { |m| body_nodes << Lit.new("extend #{m}") }
      mixins(meta[:prepend]).each { |m| body_nodes << Lit.new("prepend #{m}") }
      emit_class_body(body_forms, body_nodes)

      inner = nsf.module? ? ModuleDef.new(parts.last, body_nodes)
                          : ClassDef.new(parts.last, superclass, body_nodes)
      node = parts[0...-1].reverse.inject(inner) do |acc, mod|
        ModuleDef.new(mod, [acc])
      end
      require_nodes + [node]
    end

    # Register aliases/refers and load each (:require/:import) dependency.  In
    # compile mode, returns the runtime require/require_relative nodes to emit at
    # the top of the file; in dev mode the loader has already loaded everything
    # and we emit nothing.
    def process_requires(nsf)
      nodes = []
      (nsf.requires + nsf.imports).each do |spec|
        register_resolution(spec)
        res = @loader.load_spec(spec)
        nodes << require_node(spec, res) if @mode == :compile
      end
      nodes.compact
    end

    def register_resolution(spec)
      const = @emitter.const_path(spec.ns)
      @env.define_alias(spec.as, const) if spec.as
      Array(spec.refer == :all ? nil : spec.refer).each do |name|
        @env.define_refer(name, const)
      end
    end

    def require_node(spec, res)
      case res.kind
      when :rouge
        from = @config.output_path_for_ns(@env.current_ns)
        to = @config.output_path_for_ns(spec.ns)
        Lit.new(%(require_relative "#{@config.require_relative_between(from, to)}"))
      when :ruby
        Lit.new(%(require "#{spec.ns.tr('.', '/')}"))
      when :gem
        Lit.new(%(require "#{res.require_name}"))
      end
    end

    def emit_class_body(forms, body_nodes)
      forms.each do |form|
        node = @emitter.emit(form)
        next if node.nil?

        if node.is_a?(MethodDef) && node.visibility == :private
          body_nodes << Lit.new("private")
        end
        body_nodes << node
      end
    end

    def mixins(value)
      return [] if value.nil?

      list = value.is_a?(::Array) ? value : [value]
      list.map { |m| const_name(m) }
    end

    def const_name(sym)
      sym.to_s.tr("/", ".").split(".").join("::")
    end
  end
end

# vim: set sw=2 et cc=80:
