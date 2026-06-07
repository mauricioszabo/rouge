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

    attr_reader :env, :emitter

    def initialize(env = Rouge::Env.new)
      @env = env
      @emitter = Rouge::Emitter.new(@env)
    end

    def transpile(source, rubocop: false)
      forms = Rouge::Reader.read_all(source)
      nodes = process_forms(forms)
      ruby = Rouge::PrettyPrinter.print_all(nodes)
      rubocop ? Rouge::Formatter.rubocop(ruby) : ruby
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
      name_sym = ns_form.to_a[1]
      @env.current_ns = name_sym.to_s
      meta = name_sym.respond_to?(:meta) ? (name_sym.meta || {}) : {}

      parts = name_sym.name_parts.map { |p| @emitter.camelize(p.to_s) }
      superclass = meta[:extends] ? const_name(meta[:extends]) : nil

      body_nodes = []
      mixins(meta[:include]).each { |m| body_nodes << Lit.new("include #{m}") }
      mixins(meta[:extend]).each  { |m| body_nodes << Lit.new("extend #{m}") }
      mixins(meta[:prepend]).each { |m| body_nodes << Lit.new("prepend #{m}") }
      emit_class_body(body_forms, body_nodes)

      inner = ClassDef.new(parts.last, superclass, body_nodes)
      node = parts[0...-1].reverse.inject(inner) do |acc, mod|
        ModuleDef.new(mod, [acc])
      end
      [node]
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
