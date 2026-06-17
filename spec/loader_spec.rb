require 'spec_helper'
require 'tmpdir'
require 'fileutils'

describe Rouge::Loader do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      FileUtils.mkdir_p(File.join(dir, "src", "util"))
      File.write(File.join(dir, "src", "util", "math.rg"), "(ns util.math)")
      File.write(File.join(dir, "src", "legacy.rb"), "module Legacy; end")
      @config = Rouge::Config.new(dir, { :"source-roots" => ["src"], :"output-root" => "lib" })
      example.run
    end
  end

  def loader(mode: :compile)
    Rouge::Loader.new(@config, mode: mode, env: Rouge::Env.new)
  end

  describe "#resolve" do
    it "finds a Rouge source on the path" do
      res = loader.resolve("util.math")
      expect(res.kind).to eq :rouge
      expect(res.path).to eq File.join(@dir, "src", "util", "math.rg")
    end

    it "finds a local Ruby file on the path" do
      expect(loader.resolve("legacy").kind).to eq :ruby
    end

    it "falls back to a gem require for anything off the path" do
      res = loader.resolve("json")
      expect(res.kind).to eq :gem
      expect(res.require_name).to eq "json"
    end
  end

  describe "#runtime_require" do
    it "wires a require_relative between two compiled outputs" do
      res = loader.resolve("util.math")
      from = @config.output_path_for_ns("app")
      kw, arg = loader.runtime_require(res, from)
      expect(kw).to eq "require_relative"
      expect(arg).to eq "util/math"
    end

    it "emits a plain require for a gem" do
      kw, arg = loader.runtime_require(loader.resolve("json"), "/x.rb")
      expect([kw, arg]).to eq ["require", "json"]
    end
  end
end

# vim: set sw=2 et cc=80:
