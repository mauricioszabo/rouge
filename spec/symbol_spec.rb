# encoding: utf-8
require 'spec_helper'
require 'cursed'

describe Cursed::Symbol do
  describe "lookup" do
    it { Cursed::Symbol[:true].should be true }
    it { Cursed::Symbol[:false].should be false }
    it { Cursed::Symbol[:nil].should be nil }
  end

  describe ".[]" do
    it { Cursed::Symbol[:a].should_not be Cursed::Symbol[:a] }
    # but:
    it { Cursed::Symbol[:a].should eq Cursed::Symbol[:a] }
  end

  describe "#ns, #name" do
    it { Cursed::Symbol[:abc].ns.should be_nil }
    it { Cursed::Symbol[:abc].name.should eq :abc }
    it { Cursed::Symbol[:"abc/def"].ns.should eq :abc }
    it { Cursed::Symbol[:"abc/def"].name.should eq :def }
    it { Cursed::Symbol[:/].ns.should be_nil }
    it { Cursed::Symbol[:/].name.should eq :/ }
    it { Cursed::Symbol[:"cursed.core//"].ns.should eq :"cursed.core" }
    it { Cursed::Symbol[:"cursed.core//"].name.should eq :/ }
  end

  describe "#to_sym" do
    it { Cursed::Symbol[:boo].to_sym.should eq :boo }
    it { Cursed::Symbol[:"what/nice"].to_sym.should eq :"what/nice" }
  end

  describe "#to_s" do
    it { Cursed::Symbol[:"breakfast"].to_s.should eq "breakfast" }
    it { Cursed::Symbol[:"breakfast/toast"].to_s.should eq "breakfast/toast" }
  end
end

# vim: set sw=2 et cc=80:
