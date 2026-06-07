require 'spec_helper'

describe "defsyntax / defimpl" do
  describe "the prelude re-expresses map/reduce through the syntax system" do
    it "lowers (map ...) via the :default impl" do
      expect(emit("(map inc coll)")).to eq "coll.map { |it__1| it__1 + 1 }"
    end

    it "lowers (reduce ...) via the :default impls" do
      expect(emit("(reduce f coll)"))
        .to eq "coll.inject { |it__1, it__2| f(it__1, it__2) }"
      expect(emit("(reduce f 0 coll)"))
        .to eq "coll.inject(0) { |it__1, it__2| f(it__1, it__2) }"
    end
  end

  describe "type dispatch" do
    it "picks an impl by the dispatch fn's token" do
      src = <<~CLJ
        (defsyntax stringify (fn [x] (type-of x)))
        (defimpl stringify :default [x] `(.to-s ~x))
        (defimpl stringify :vector [x] `(.join ~x ","))
        (defn a [^Integer n] (stringify n))
        (defn b [^Array xs] (stringify xs))
      CLJ
      ruby = transpile(src)
      expect(ruby).to include("def a(n)\n  n.to_s")
      expect(ruby).to include("def b(xs)\n  xs.join(\",\")")
    end

    it "dispatches on a bareword class tag (^OpenStruct) to the right impl" do
      expect(transpile("(defn f [^OpenStruct o] (map inc o))"))
        .to include("o.to_h.map { |it__1| it__1 + 1 }")
    end

    it "falls back to :default when no exact impl matches" do
      src = <<~CLJ
        (defsyntax g (fn [x] (type-of x)))
        (defimpl g :default [x] `(.foo ~x))
        (defn a [^OpenStruct o] (g o))
      CLJ
      expect(transpile(src)).to include("o.foo")
    end
  end

  describe ":missing" do
    it "uses the :missing impl and warns when the type is unknown" do
      src = <<~CLJ
        (defsyntax g (fn [x] (type-of x)))
        (defimpl g :missing [x] `(.bar ~x))
        (defn a [x] (g x))
      CLJ
      ruby = nil
      expect { ruby = transpile(src) }
        .to output(/unresolved dispatch type.*:missing/).to_stderr
      expect(ruby).to include("x.bar")
    end
  end

  describe ":vararg and apply" do
    it "maps over several collections in parallel" do
      expect(emit("(map + a b)"))
        .to eq "a.zip(b).map { |it__1, it__2| it__1 + it__2 }"
    end

    it "routes (apply syntax ...) through the :vararg impl" do
      expect(emit("(fn [g xs] (apply map g xs))"))
        .to eq "->(g, xs) { xs.map(&g) }"
    end
  end

  describe "^:block params" do
    it "splices a function param as a Ruby block" do
      src = <<~CLJ
        (defsyntax each2 (fn [f coll] (type-of coll)))
        (defimpl each2 :default [^:block f coll] `(.each ~coll ~f))
        (defn run [coll] (each2 println coll))
      CLJ
      expect(transpile(src)).to include("coll.each { |it__1| puts(it__1) }")
    end

    it "honours an explicit block arity ^{:block 2}" do
      src = <<~CLJ
        (defsyntax fold (fn [f coll] (type-of coll)))
        (defimpl fold :default [^{:block 2} f coll] `(.inject ~coll ~f))
        (defn run [coll] (fold g coll))
      CLJ
      expect(transpile(src))
        .to include("coll.inject { |it__1, it__2| g(it__1, it__2) }")
    end
  end

  describe ".. (interop threading)" do
    it "threads a receiver through method/step calls" do
      expect(emit("(.. obj to-h (slice :a :b) (to-a))"))
        .to eq "obj.to_h.slice(:a, :b).to_a"
    end
  end

  describe "defsyntax/defimpl themselves" do
    it "produce no output" do
      src = <<~CLJ
        (defsyntax noop (fn [x] (type-of x)))
        (defimpl noop :default [x] x)
      CLJ
      expect(transpile(src).strip).to eq ""
    end
  end

  describe "end-to-end" do
    it "runs the generated Ruby for default, parallel and apply maps" do
      ruby = transpile(<<~CLJ)
        (defn padd [a b] (map + a b))
        (defn apply-map [g xs] (apply map g xs))
        (defn total [coll] (reduce + coll))
      CLJ
      klass = Class.new { eval(ruby) } # rubocop:disable Security/Eval
      obj = klass.new
      expect(obj.padd([1, 2, 3], [10, 20, 30])).to eq [11, 22, 33]
      expect(obj.apply_map(->(x) { x + 1 }, [10, 20])).to eq [11, 21]
      expect(obj.total([1, 2, 3, 4])).to eq 10
    end
  end
end

# vim: set sw=2 et cc=80:
