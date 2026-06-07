require 'spec_helper'

describe "macros" do
  it "expands a user macro defined earlier in the same source" do
    src = <<~CLJ
      (defmacro unless2 [c body] `(if ~c nil ~body))
      (defn t [x] (unless2 (nil? x) (.process x)))
    CLJ
    expect(transpile(src)).to eq <<~RUBY
      def t(x)
        x.nil? ? nil : x.process
      end
    RUBY
  end

  it "macro bodies can splice rest args" do
    src = <<~CLJ
      (defmacro my-when [c & body] `(if ~c (do ~@body) nil))
      (defn t [] (my-when x (a) (b)))
    CLJ
    ruby = transpile(src)
    expect(ruby).to include("if x")
    expect(ruby).to include("a")
    expect(ruby).to include("b")
  end

  it "produces no output for the defmacro itself" do
    expect(transpile("(defmacro noop [x] x)").strip).to eq ""
  end

  it "expansion can run arbitrary Ruby at transpile time" do
    # The macro computes a literal using host Ruby during expansion.
    src = <<~CLJ
      (defmacro inc-lit [n] (.+ n 1))
      (defn t [] (inc-lit 41))
    CLJ
    expect(transpile(src)).to include("42")
  end
end
