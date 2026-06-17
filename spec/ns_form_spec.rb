require 'spec_helper'

describe Rouge::NsForm do
  def parse(src)
    described_class.parse(Rouge::Reader.read_all(src).first)
  end

  it "reads the namespace name" do
    expect(parse("(ns my.app.core)").name).to eq "my.app.core"
  end

  it "parses :require libspecs with :as and :refer" do
    nsf = parse("(ns app (:require [a.b :as x :refer [f g]] [c.d :as y]))")
    expect(nsf.requires.map(&:ns)).to eq ["a.b", "c.d"]
    first = nsf.requires.first
    expect(first.as).to eq "x"
    expect(first.refer).to eq ["f", "g"]
    expect(first.kind).to eq :require
    expect(nsf.requires.last.as).to eq "y"
  end

  it "parses :refer :all" do
    nsf = parse("(ns app (:require [a.b :refer :all]))")
    expect(nsf.requires.first.refer).to eq :all
  end

  it "parses :import as gem specs" do
    nsf = parse("(ns app (:import [json] [csv]))")
    expect(nsf.imports.map(&:ns)).to eq ["json", "csv"]
    expect(nsf.imports.first.kind).to eq :import
  end

  it "detects a module-flavoured namespace via ^:module" do
    expect(parse("(ns ^:module util.math)").module?).to be true
    expect(parse("(ns app)").module?).to be false
  end
end

# vim: set sw=2 et cc=80:
