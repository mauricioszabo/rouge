require 'spec_helper'

describe Rouge::Interpreter do
  it "transpiles-then-evals an expression" do
    expect(Rouge::Interpreter.new.eval_str("(+ 1 2)")).to eq 3
  end

  it "evaluates core seq mappings against real Ruby" do
    expect(Rouge::Interpreter.new.eval_str("(reduce + (map inc [1 2 3]))")).to eq 9
  end

  it "persists state (a def) across forms in one session" do
    interp = described_class.new
    interp.eval_str("(defn sq [x] (* x x))")
    expect(interp.eval_str("(sq 9)")).to eq 81
  end

  it "lets a macro defined in a session drive later forms" do
    interp = described_class.new
    result = interp.eval_str(<<~CLJ)
      (defmacro twice [x] `(* 2 ~x))
      (twice 21)
    CLJ
    expect(result).to eq 42
  end

  it "exposes the emitted Ruby for a form" do
    form = Rouge::Reader.read_all("(map inc xs)").first
    expect(described_class.new.transpile_form(form)).to eq "xs.map { |it__1| it__1 + 1 }"
  end
end
