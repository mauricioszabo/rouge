require 'spec_helper'

# Transpile-level behaviour of (ns ... (:require ...)) clauses, aliases, refers
# and module-flavoured namespaces.  Off-path namespaces resolve as gems, so
# these need no fixtures on disk.
describe "namespaces, require, aliases" do
  describe ":require emission" do
    it "emits a plain require for an off-path namespace (gem fallback)" do
      ruby = transpile("(ns app (:require [other.ns :as o]))\n(defn f [] (o/foo 1))")
      expect(ruby).to include('require "other/ns"')
    end

    it "emits a require for an :import gem" do
      expect(transpile("(ns app (:import [json]))")).to include('require "json"')
    end
  end

  describe "alias resolution" do
    it "resolves an aliased qualified call to the namespace const path" do
      ruby = transpile("(ns app (:require [other.ns :as o]))\n(defn f [x] (o/foo x))")
      expect(ruby).to include("Other::Ns.foo(x)")
    end

    it "resolves an aliased constant" do
      ruby = transpile("(ns app (:require [util.thing :as u]))\n(defn f [] u/CONST)")
      expect(ruby).to include("Util::Thing::CONST")
    end
  end

  describe "refer resolution" do
    it "resolves a bare referred name to a call on its namespace" do
      ruby = transpile("(ns app (:require [util.math :as m :refer [square]]))\n" \
                       "(defn f [x] (square x))")
      expect(ruby).to include("Util::Math.square(x)")
    end
  end

  describe "per-namespace macro scope" do
    # One Env across both files, so we can observe cross-namespace visibility.
    def transpile_files(*sources)
      env = Rouge::Env.new
      t = Rouge::Transpiler.new(env)
      sources.map { |s| t.transpile(s) }
    end

    it "expands a macro defined in the same namespace" do
      ruby = transpile("(ns a)\n(defmacro twice [x] `(* 2 ~x))\n(defn f [n] (twice n))")
      expect(ruby).to include("2 * n")
    end

    it "does NOT expand a macro from another namespace that wasn't required" do
      _a, b = transpile_files(
        "(ns a)\n(defmacro twice [x] `(* 2 ~x))",
        "(ns b)\n(defn f [n] (twice n))"
      )
      # Unrequired: 'twice' is not a macro here, so it stays a plain call.
      expect(b).to include("twice(n)")
      expect(b).not_to include("2 * n")
    end

    it "expands a macro brought in unqualified via :refer" do
      _a, b = transpile_files(
        "(ns a)\n(defmacro twice [x] `(* 2 ~x))",
        "(ns b (:require [a :refer [twice]]))\n(defn f [n] (twice n))"
      )
      expect(b).to include("2 * n")
    end

    it "expands a macro called qualified (aliased) without :refer" do
      _a, b = transpile_files(
        "(ns a)\n(defmacro twice [x] `(* 2 ~x))",
        "(ns b (:require [a :as a]))\n(defn f [n] (a/twice n))"
      )
      expect(b).to include("2 * n")
    end

    it "supports :refer :all for macros" do
      _a, b = transpile_files(
        "(ns a)\n(defmacro twice [x] `(* 2 ~x))",
        "(ns b (:require [a :refer :all]))\n(defn f [n] (twice n))"
      )
      expect(b).to include("2 * n")
    end
  end

  describe "module-flavoured namespaces" do
    it "emits a module whose defns are module functions" do
      expect(transpile("(ns ^:module util.math)\n(defn square [n] (* n n))")).to eq <<~RUBY
        module Util
          module Math
            def self.square(n)
              n * n
            end
          end
        end
      RUBY
    end

    it "a default namespace stays a class with instance methods" do
      expect(transpile("(ns app)\n(defn f [n] n)")).to include("class App\n  def f(n)")
    end
  end
end

# vim: set sw=2 et cc=80:
