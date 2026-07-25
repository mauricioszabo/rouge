require 'spec_helper'

# The reader is reused from the original Cursed project; these specs cover the
# slimmed-down API (Reader.read_all) the transpiler relies on.
describe Cursed::Reader do
  def read_one(s)
    Cursed::Reader.read_all(s).first
  end

  it "reads scalars" do
    expect(read_one("42")).to eq 42
    expect(read_one("1.5")).to eq 1.5
    expect(read_one('"hi"')).to eq "hi"
    expect(read_one(":kw")).to eq :kw
    expect(read_one("true")).to eq true
    expect(read_one("nil")).to be_nil
  end

  it "reads symbols with namespaces" do
    sym = read_one("foo.bar/baz")
    expect(sym).to be_a(Cursed::Symbol)
    expect(sym.ns_s).to eq "foo.bar"
    expect(sym.name_s).to eq "baz"
  end

  it "reads collections" do
    expect(read_one("[1 2 3]")).to eq [1, 2, 3]
    expect(read_one("{:a 1}")).to eq({ a: 1 })
    expect(read_one("(a b c)")).to be_a(Cursed::Seq::Cons)
  end

  it "reads metadata onto symbols" do
    sym = read_one("^:block f")
    expect(sym.meta).to eq({ block: true })
  end

  it "expands #( ) into an fn form" do
    form = read_one("#(+ % 1)").to_a
    expect(form[0]).to eq Cursed::Symbol[:fn]
  end

  it "reads every top-level form" do
    expect(Cursed::Reader.read_all("(a) (b) (c)").length).to eq 3
  end
end
