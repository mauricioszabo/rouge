require 'spec_helper'

RA = Rouge::RubyAST

describe Rouge::PrettyPrinter do
  Lit = RA::Lit
  Call = RA::Call
  BlockFn = RA::BlockFn
  MethodDef = RA::MethodDef
  HashLit = RA::HashLit

  let(:pp) { Rouge::PrettyPrinter.new }

  it "indents method bodies with two spaces" do
    node = MethodDef.new("foo", ["a"], [Lit.new("a")])
    expect(pp.render(node)).to eq <<~RUBY.strip
      def foo(a)
        a
      end
    RUBY
  end

  it "omits parens for zero-arg methods" do
    node = MethodDef.new("foo", [], [Lit.new("1")])
    expect(pp.render(node)).to eq "def foo\n  1\nend"
  end

  it "renders a single-line block with braces" do
    call = Call.new(Lit.new("coll"), "map", [], block: BlockFn.new(["x"], [Lit.new("x")]))
    expect(pp.render(call)).to eq "coll.map { |x| x }"
  end

  it "renders a multi-statement block with do/end" do
    call = Call.new(Lit.new("coll"), "each", [],
                    block: BlockFn.new(["x"], [Lit.new("a"), Lit.new("b")]))
    expect(pp.render(call)).to eq <<~RUBY.strip
      coll.each do |x|
        a
        b
      end
    RUBY
  end

  it "uses symbol-key shorthand in hashes" do
    node = HashLit.new([[Lit.new(":a"), Lit.new("1")]])
    expect(pp.render(node)).to eq "{ a: 1 }"
  end

  it "uses hash-rocket for non-symbol keys" do
    node = HashLit.new([[Lit.new('"x"'), Lit.new("1")]])
    expect(pp.render(node)).to eq '{ "x" => 1 }'
  end
end
