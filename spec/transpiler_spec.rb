require 'spec_helper'

describe Cursed::Transpiler do
  describe "the sample fixture" do
    let(:ruby) { transpile(File.read(relative_to_spec("fixtures/sample.clj"))) }

    it "produces syntactically valid Ruby" do
      expect(RubyVM::InstructionSequence.compile(ruby)).to be_truthy
    end

    it "wraps everything in the namespace class" do
      expect(ruby).to include("class Calculator < Object")
      expect(ruby).to include("include Comparable")
    end

    it "expands the defop macro into methods" do
      expect(ruby).to include("def add(a, b)")
      expect(ruby).to include("def mul(a, b)")
      expect(ruby).to include("a + b")
      expect(ruby).to include("a * b")
    end

    it "maps core fns" do
      expect(ruby).to include("coll.select { |it")
      expect(ruby).to include(".inject")
    end

    it "honours block-param metadata" do
      expect(ruby).to include("def each_doubled(coll, &f)")
    end
  end

  describe "evaluating the generated Ruby" do
    it "runs end-to-end and computes the right value" do
      ruby = transpile(<<~CLJ)
        (defn sum-evens [coll] (reduce + (filter even? coll)))
      CLJ
      # Define the method on a throwaway object and call it.
      klass = Class.new { eval(ruby) } # rubocop:disable Security/Eval
      expect(klass.new.sum_evens([1, 2, 3, 4, 5, 6])).to eq 12
    end
  end
end
