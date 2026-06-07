require 'spec_helper'

describe "core fn mappings" do
  describe "sequence fns operate on the last argument" do
    it { expect(emit("(map inc coll)")).to eq "coll.map { |it__1| it__1 + 1 }" }
    it { expect(emit("(map :name coll)")).to eq "coll.map(&:name)" }
    it { expect(emit("(filter even? coll)")).to eq "coll.select { |it__1| it__1.even? }" }
    it { expect(emit("(remove nil? coll)")).to eq "coll.reject { |it__1| it__1.nil? }" }
    it { expect(emit("(map (fn [x] (* x 2)) coll)")).to eq "coll.map { |x| x * 2 }" }
    it { expect(emit("(count coll)")).to eq "coll.size" }
    it { expect(emit("(first coll)")).to eq "coll.first" }
    it { expect(emit("(rest coll)")).to eq "coll.drop(1)" }
    it { expect(emit("(take 3 coll)")).to eq "coll.take(3)" }
    it { expect(emit("(sort-by :age coll)")).to eq "coll.sort_by(&:age)" }

    it "passes a bound local fn as a block" do
      expect(emit("(fn [f coll] (map f coll))")).to eq "->(f, coll) { coll.map(&f) }"
    end
  end

  describe "reduce -> inject" do
    it { expect(emit("(reduce f coll)")).to eq "coll.inject { |it__1, it__2| f(it__1, it__2) }" }
    it { expect(emit("(reduce f 0 coll)")).to eq "coll.inject(0) { |it__1, it__2| f(it__1, it__2) }" }
  end

  describe "maps" do
    it { expect(emit("(get m :k)")).to eq "m[:k]" }
    it { expect(emit("(get m :k 0)")).to eq "m.fetch(:k, 0)" }
    it { expect(emit("(assoc m :k 1)")).to eq "m.merge({ k: 1 })" }
    it { expect(emit("(dissoc m :k)")).to eq "m.except(:k)" }
    it { expect(emit("(keys m)")).to eq "m.keys" }
    it { expect(emit("(merge a b)")).to eq "a.merge(b)" }
  end

  describe "type-hint-driven conj" do
    it "uses + for vectors" do
      expect(emit("(let [^:vector v [1]] (conj v 2))")).to eq <<~RUBY.strip
        v = [1]
        v + [2]
      RUBY
    end

    it "uses merge for maps" do
      expect(emit("(let [^:map m {}] (conj m [:a 1]))")).to eq <<~RUBY.strip
        m = {}
        m.merge({ a: 1 })
      RUBY
    end

    it "infers vector type from a literal binding" do
      expect(emit("(let [v [1 2]] (conj v 3))")).to eq <<~RUBY.strip
        v = [1, 2]
        v + [3]
      RUBY
    end
  end

  describe "strings" do
    it { expect(emit('(str "a" x "b")')).to eq '"a#{x}b"' }
    it { expect(emit("(println x)")).to eq "puts(x)" }
    it { expect(emit("(upper-case s)")).to eq "s.upcase" }
    it { expect(emit("(clojure.string/upper-case s)")).to eq "s.upcase" }
  end

  describe "predicates" do
    it { expect(emit("(nil? x)")).to eq "x.nil?" }
    it { expect(emit("(empty? x)")).to eq "x.empty?" }
    it { expect(emit("(instance? String x)")).to eq "x.is_a?(String)" }
  end
end
