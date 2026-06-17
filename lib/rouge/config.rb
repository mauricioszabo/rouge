# encoding: utf-8

require 'pathname'

module Rouge
  # Per-project configuration, read from a +rouge.edn+ at (or above) the project
  # root.  Declares where Rouge sources live and where compiled Ruby is written.
  #
  #   {:source-roots ["src"]
  #    :output-root  "lib"}
  #
  # Defaults to a mirrored +src/ -> lib/+ layout when no config is found.
  class Config
    ROUGE_EXTS = %w[.rg .clj .rouge].freeze
    CONFIG_NAME = "rouge.edn".freeze

    attr_reader :root, :source_roots, :output_root

    def self.load(start_dir = Dir.pwd)
      dir = find_config_dir(start_dir)
      data = dir ? (Rouge::Reader.read_all(File.read(File.join(dir, CONFIG_NAME))).first || {}) : {}
      new(dir || start_dir, data)
    end

    def self.find_config_dir(start)
      dir = File.expand_path(start)
      loop do
        return dir if File.exist?(File.join(dir, CONFIG_NAME))

        parent = File.dirname(dir)
        return nil if parent == dir

        dir = parent
      end
    end

    def initialize(root, data = {})
      @root = File.expand_path(root)
      srcs = data[:"source-roots"] || ["src"]
      @source_roots = Array(srcs).map { |s| File.expand_path(s, @root) }
      @output_root = File.expand_path(data[:"output-root"] || "lib", @root)
    end

    # The source root that contains an absolute path, or nil.
    def source_root_for(abs_path)
      @source_roots.find { |r| abs_path == r || abs_path.start_with?(r + File::SEPARATOR) }
    end

    # Map an absolute Rouge source path to its compiled +.rb+ output path,
    # mirroring the tree under +output_root+.
    def output_path_for(source_abs)
      root = source_root_for(source_abs)
      rel = root ? source_abs[(root.length + 1)..] : File.basename(source_abs)
      File.join(@output_root, rel.sub(/\.(rg|clj|rouge)\z/, ".rb"))
    end

    # The compiled output path for a dotted namespace name (mirrored layout),
    # independent of where the source happens to live.
    def output_path_for_ns(ns_string)
      File.join(@output_root, ns_string.tr(".", File::SEPARATOR) + ".rb")
    end

    # The argument for a +require_relative+ in +from_out+ that loads +to_out+
    # (both absolute output paths), without the +.rb+ suffix.
    def require_relative_between(from_out, to_out)
      from_dir = Pathname.new(File.dirname(from_out))
      Pathname.new(to_out.sub(/\.rb\z/, "")).relative_path_from(from_dir).to_s
    end
  end
end

# vim: set sw=2 et cc=80:
