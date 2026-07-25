require 'spec_helper'
require 'tmpdir'
require 'fileutils'

describe Cursed::Compiler do
  def write(dir, rel, body)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  def compile!
    Cursed::Compiler.new(Cursed::Config.load(@dir)).compile_all
  end

  it "compiles a multi-file project in dependency order to plain Ruby" do
    write(@dir, "cursed.edn", '{:source-roots ["src"] :output-root "lib"}')
    write(@dir, "src/util/math.rg", <<~CLJ)
      (ns ^:module util.math)
      (defmacro double [x] `(* 2 ~x))
      (defn square [n] (* n n))
    CLJ
    write(@dir, "src/app.rg", <<~CLJ)
      (ns app
        (:require [util.math :as m :refer [square double]]
                  [set :as s]))
      (defn demo [n] (+ (m/square n) (square n) (double 5)))
    CLJ

    written = compile!
    expect(written.map { |w| File.basename(w) }).to contain_exactly("math.rb", "app.rb")

    app = File.read(File.join(@dir, "lib", "app.rb"))
    expect(app).to include('require_relative "util/math"')
    expect(app).to include('require "set"')
    expect(app).to include("Util::Math.square(n)")  # both alias and refer
    expect(app).to include("2 * 5")                  # refer'd macro expanded at compile time
  end

  it "produces output free of any Cursed runtime reference" do
    write(@dir, "cursed.edn", '{:source-roots ["src"] :output-root "lib"}')
    write(@dir, "src/util/math.rg", "(ns ^:module util.math)\n(defn square [n] (* n n))")
    write(@dir, "src/app.rg", <<~CLJ)
      (ns app (:require [util.math :as m]))
      (defn demo [n] (m/square n))
    CLJ
    compile!
    Dir.glob(File.join(@dir, "lib", "**", "*.rb")).each do |f|
      expect(File.read(f)).not_to include("Cursed::")
    end
  end

  it "runs the compiled output under plain ruby (no Cursed loaded)" do
    write(@dir, "cursed.edn", '{:source-roots ["src"] :output-root "lib"}')
    write(@dir, "src/util/math.rg", "(ns ^:module util.math)\n(defn square [n] (* n n))")
    write(@dir, "src/app.rg", <<~CLJ)
      (ns app (:require [util.math :as m :refer [square]]))
      (defn demo [n] (+ (m/square n) (square n)))
    CLJ
    compile!

    lib = File.join(@dir, "lib")
    out = `ruby -I#{lib} -e 'require "app"; print App.new.demo(3)'`
    expect(out).to eq "18"
  end

  it "raises on a circular dependency" do
    write(@dir, "cursed.edn", '{:source-roots ["src"] :output-root "lib"}')
    write(@dir, "src/a.rg", "(ns a (:require [b :as b]))")
    write(@dir, "src/b.rg", "(ns b (:require [a :as a]))")
    expect { compile! }.to raise_error(Cursed::Compiler::CircularDependency)
  end
end

# vim: set sw=2 et cc=80:
