# encoding: utf-8

require 'fileutils'

module Cursed
  # Ahead-of-time project compiler.  Discovers every Cursed source under the
  # configured source roots, builds a dependency graph from each file's
  # +(ns ... (:require ...))+, compiles in topological order through ONE shared
  # Env (so a dependency's macros/syntaxes are registered before its dependents
  # compile), and writes mirrored plain-Ruby +.rb+ files to the output root.
  #
  # The emitted Ruby is standalone: macros/syntaxes have fully expanded and the
  # only cross-file links are ordinary +require_relative+/+require+ statements —
  # no Cursed runtime is needed to run the result.
  class Compiler
    class CircularDependency < StandardError; end

    def initialize(config = Cursed::Config.load)
      @config = config
      @env = Cursed::Env.new
      @transpiler = Cursed::Transpiler.new(@env, config: @config, mode: :compile)
      @loader = @transpiler.loader
    end

    # Compile the whole project.  Returns the list of written output paths.
    def compile_all
      graph = build_graph(source_files)
      topo_sort(graph).map { |ns| compile_entry(graph[ns]) }
    end

    private

    def source_files
      @config.source_roots.flat_map do |root|
        Config::CURSED_EXTS.flat_map { |ext| Dir.glob(File.join(root, "**", "*#{ext}")) }
      end.uniq
    end

    # ns name => { path:, deps: [ns, ...], forms: [...] }
    def build_graph(files)
      graph = {}
      files.each do |path|
        forms = Cursed::Reader.read_all(File.read(path))
        ns_form = forms.find { |f| ns_form?(f) }
        next unless ns_form

        nsf = Cursed::NsForm.parse(ns_form)
        deps = nsf.requires.select { |s| @loader.resolve(s.ns).cursed? }.map(&:ns)
        graph[nsf.name] = { ns: nsf.name, path: path, deps: deps, forms: forms }
      end
      graph
    end

    def topo_sort(graph)
      order = []
      visited = {}
      stack = {}
      visit = lambda do |ns|
        return if visited[ns]
        raise CircularDependency, "circular require involving #{ns}" if stack[ns]

        stack[ns] = true
        graph[ns][:deps].each { |d| visit.call(d) if graph.key?(d) }
        stack.delete(ns)
        visited[ns] = true
        order << ns
      end
      graph.keys.each { |ns| visit.call(ns) }
      order
    end

    def compile_entry(entry)
      ruby = @transpiler.transpile_forms(entry[:forms])
      out = @config.output_path_for(entry[:path])
      FileUtils.mkdir_p(File.dirname(out))
      File.write(out, ruby)
      @loader.note_compiled(entry[:ns], entry[:path])
      out
    end

    def ns_form?(form)
      (form.is_a?(Cursed::Seq::Cons) || form.is_a?(Cursed::Seq::ISeq)) &&
        form.to_a[0].is_a?(Cursed::Symbol) && form.to_a[0].name_s == "ns"
    end
  end
end

# vim: set sw=2 et cc=80:
