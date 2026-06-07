require 'spec_helper'

describe "special forms and namespaces" do
  describe "ns -> class" do
    it "maps a namespace to nested modules + class" do
      expect(transpile("(ns my.app.core)")).to eq <<~RUBY
        module My
          module App
            class Core
            end
          end
        end
      RUBY
    end

    it "uses :extends metadata as the superclass" do
      ruby = transpile("(ns ^{:extends ApplicationRecord} my.user)")
      expect(ruby).to include("class User < ApplicationRecord")
    end

    it "emits include/extend from metadata" do
      ruby = transpile("(ns ^{:include [Comparable Enumerable]} my.thing)")
      expect(ruby).to include("include Comparable")
      expect(ruby).to include("include Enumerable")
    end
  end

  describe "defn -> method" do
    it "becomes an instance method" do
      expect(transpile('(defn greet [nm] (str "hi " nm))')).to eq <<~'RUBY'
        def greet(nm)
          "hi #{nm}"
        end
      RUBY
    end

    it "emits a class method with ^:self" do
      expect(transpile("(defn ^:self build [] 1)")).to include("def self.build")
    end

    it "groups private methods under `private`" do
      ruby = transpile("(ns my.x)\n(defn pub [] 1)\n(defn- priv [] 2)")
      expect(ruby).to include("private")
      expect(ruby.index("private")).to be < ruby.index("def priv")
    end

    it "handles rest args" do
      expect(transpile("(defn f [a & rest] rest)")).to include("def f(a, *rest)")
    end
  end

  describe "block params via metadata" do
    it { expect(transpile("(defn run [^:block f] (f))")).to include("def run(&f)") }
  end

  describe "class mechanics" do
    it "emits refine with a block" do
      ruby = transpile("(ns my.r)\n(refine String (defn shout [] (.upcase self)))")
      expect(ruby).to include("refine(String) do")
    end
  end

  describe "threading macros" do
    it { expect(emit("(-> x (f 1) (g 2))")).to eq "g(f(x, 1), 2)" }
    it "threads as the last argument" do
      expect(emit("(->> x (map f) (filter g))"))
        .to eq "x.map { |it__1| f(it__1) }.select { |it__2| g(it__2) }"
    end
  end

  describe "cond / case / when" do
    it "emits cond as if/elsif/else" do
      expect(emit("(cond a 1 b 2 :else 3)")).to eq <<~RUBY.strip
        if a
          1
        elsif b
          2
        else
          3
        end
      RUBY
    end

    it "emits when" do
      expect(emit("(when a (foo) (bar))")).to eq <<~RUBY.strip
        if a
          foo
          bar
        end
      RUBY
    end
  end

  describe "try / catch / finally" do
    it "emits begin/rescue/ensure" do
      ruby = emit("(try (foo) (catch StandardError e (bar e)) (finally (baz)))")
      expect(ruby).to include("rescue StandardError => e")
      expect(ruby).to include("ensure")
    end
  end
end
