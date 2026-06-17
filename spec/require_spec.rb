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
