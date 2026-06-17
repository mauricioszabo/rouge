# encoding: utf-8

module Rouge
  # Resolves a namespace reference to a file (or gem) and loads it, in one of two
  # modes:
  #
  #  * +:dev+   — used by the Interpreter / nREPL.  A Rouge dep is transpiled and
  #    evaluated into the *live session* so its defs/macros/syntaxes are usable
  #    immediately; a Ruby file or gem is +require+d into the process.
  #  * +:compile+ — used by the project Compiler.  A Rouge dep's forms are
  #    processed through the shared compiler Env so its macros/syntaxes register
  #    (no output inlined); the requiring file later emits a +require_relative+
  #    to the dep's *compiled* file.  Ruby/gem deps emit a runtime +require+.
  #
  # The driver supplies +load_rouge_source+: a callback that processes a resolved
  # Rouge file in the way that mode demands (eval vs. macro-register).  The Loader
  # owns resolution, the loaded-set and cycle detection; it does NOT own the Env.
  class Loader
    class CircularRequire < StandardError; end

    Resolution = Struct.new(:kind, :path, :require_name) do
      def rouge? = kind == :rouge
      def ruby?  = kind == :ruby
      def gem?   = kind == :gem
    end

    attr_accessor :load_rouge_source

    def initialize(config, mode:, env:)
      @config = config
      @mode = mode
      @env = env
      @loaded = {}     # ns string => Resolution
      @loading = []    # stack of ns strings currently loading (cycle guard)
      @resolutions = {}
    end

    # Resolve a dotted namespace to a file/gem.  +:import+ specs skip the path
    # probe and go straight to a gem require.
    def resolve(ns_string, force_gem: false)
      return gem_resolution(ns_string) if force_gem

      @resolutions[ns_string] ||= probe(ns_string)
    end

    # Load one parsed +NsForm::Spec+.  Returns its Resolution (for require wiring).
    def load_spec(spec)
      res = resolve(spec.ns, force_gem: spec.kind == :import)
      return res if @loaded.key?(spec.ns)

      case res.kind
      when :rouge      then load_rouge(spec.ns, res)
      when :ruby, :gem then load_ruby(res)
      end
      @loaded[spec.ns] = res
      res
    end

    # Record that a namespace has already been compiled (by the project
    # Compiler), so a later dependent's +:require+ won't re-macro-load it.
    def note_compiled(ns_string, path)
      @loaded[ns_string] = Resolution.new(:rouge, path, nil)
    end

    # The string a compiled file should pass to +require_relative+/+require+ to
    # load this dependency at runtime, given the requiring file's output path.
    def runtime_require(res, from_output_path)
      case res.kind
      when :rouge
        ["require_relative", @config.require_relative_between(from_output_path,
                                                              @config.output_path_for(res.path))]
      when :ruby
        ["require_relative", @config.require_relative_between(from_output_path, res.path)]
      when :gem
        ["require", res.require_name]
      end
    end

    private

    def load_rouge(ns_string, res)
      raise CircularRequire, "circular require: #{(@loading + [ns_string]).join(' -> ')}" \
        if @loading.include?(ns_string)
      raise "no Rouge loader configured" unless @load_rouge_source

      @loading.push(ns_string)
      snapshot = @env.ns_snapshot
      begin
        @load_rouge_source.call(res.path)
      ensure
        @env.restore_ns(snapshot)
        @loading.pop
      end
    end

    def load_ruby(res)
      return unless @mode == :dev # compile mode only emits a require line

      res.gem? ? require(res.require_name) : require(res.path)
    end

    def probe(ns_string)
      rel = ns_string.tr(".", File::SEPARATOR)
      @config.source_roots.each do |root|
        Config::ROUGE_EXTS.each do |ext|
          path = File.join(root, rel + ext)
          return Resolution.new(:rouge, path, nil) if File.file?(path)
        end
        rb = File.join(root, rel + ".rb")
        return Resolution.new(:ruby, rb, nil) if File.file?(rb)
      end
      gem_resolution(ns_string)
    end

    def gem_resolution(ns_string)
      Resolution.new(:gem, nil, ns_string.tr(".", File::SEPARATOR))
    end
  end
end

# vim: set sw=2 et cc=80:
