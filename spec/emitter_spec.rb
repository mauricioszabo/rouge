require 'spec_helper'

describe Rouge::Emitter do
  describe "literals" do
    it { expect(emit("42")).to eq "42" }
    it { expect(emit("1.5")).to eq "1.5" }
    it { expect(emit('"hi"')).to eq '"hi"' }
    it { expect(emit("true")).to eq "true" }
    it { expect(emit("nil")).to eq "nil" }
    it { expect(emit(":foo")).to eq ":foo" }
    it { expect(emit(":foo-bar")).to eq ':"foo-bar"' }
    it { expect(emit("[1 2 3]")).to eq "[1, 2, 3]" }
    it { expect(emit("{:a 1 :b 2}")).to eq "{ a: 1, b: 2 }" }
    it { expect(emit('{"x" 1}')).to eq '{ "x" => 1 }' }
  end

  describe "interop" do
    it { expect(emit("(.upcase s)")).to eq "s.upcase" }
    it { expect(emit("(.push coll x)")).to eq "coll.push(x)" }
    it { expect(emit("(Klass. 1 2)")).to eq "Klass.new(1, 2)" }
    it { expect(emit("(Foo/bar 1)")).to eq "Foo.bar(1)" }
    it { expect(emit("Math/PI")).to eq "Math::PI" }
    it { expect(emit("(.each coll | f)")).to eq "coll.each(&f)" }
  end

  describe "let / if / do / fn" do
    it "emits let as sequential assignments" do
      expect(emit("(let [a 1 b 2] (+ a b))")).to eq <<~RUBY.strip
        a = 1
        b = 2
        a + b
      RUBY
    end

    it "emits a simple if as a ternary" do
      expect(emit("(if x 1 2)")).to eq "x ? 1 : 2"
    end

    it "emits an if with a statement branch as an if/end" do
      expect(emit("(if x (do (foo) 1) 2)")).to eq <<~RUBY.strip
        if x
          foo
          1
        else
          2
        end
      RUBY
    end

    it { expect(emit("(fn [x] (* x x))")).to eq "->(x) { x * x }" }
  end

  describe "arithmetic and comparison" do
    it { expect(emit("(+ a b c)")).to eq "a + b + c" }
    it { expect(emit("(- a)")).to eq "-a" }
    it { expect(emit("(= a b)")).to eq "a == b" }
    it { expect(emit("(not= a b)")).to eq "!(a == b)" }
    it { expect(emit("(< a b c)")).to eq "a < b && b < c" }
    it { expect(emit("(and a b)")).to eq "a && b" }
    it { expect(emit("(inc x)")).to eq "x + 1" }
  end
end
