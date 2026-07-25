# encoding: utf-8

module Cursed
  # Parses the clauses of an +(ns ...)+ form into plain data the transpiler /
  # interpreter / loader can act on:
  #
  #   (ns ^:module my.app.foo
  #     (:require [other.ns :as o :refer [helper]]
  #               [util.math :as m])
  #     (:import [json]))
  #
  # +:require+ resolves uniformly to a Cursed namespace, a local Ruby file, or a
  # gem (decided later by the Loader).  +:import+ is the raw-gem escape hatch.
  class NsForm
    # A single libspec.  +ns+ is the dotted namespace string; +as+ an alias;
    # +refer+ a list of names or +:all+; +kind+ is +:require+ or +:import+.
    Spec = Struct.new(:ns, :as, :refer, :kind)

    attr_reader :name_sym, :requires, :imports

    def self.parse(ns_form)
      new(ns_form)
    end

    def initialize(ns_form)
      arr = ns_form.to_a
      @name_sym = arr[1]
      @requires = []
      @imports = []
      arr[2..].each { |clause| parse_clause(clause) }
    end

    def name
      @name_sym.to_s
    end

    def meta
      @name_sym.respond_to?(:meta) ? (@name_sym.meta || {}) : {}
    end

    def module?
      !!meta[:module]
    end

    private

    def parse_clause(clause)
      return unless list?(clause)

      c = clause.to_a
      kw = clause_keyword(c[0])
      case kw
      when :require
        c[1..].each { |spec| @requires << parse_spec(spec, :require) }
      when :import
        c[1..].each { |spec| @imports << parse_spec(spec, :import) }
      end
    end

    def clause_keyword(head)
      case head
      when ::Symbol then head
      when Cursed::Symbol then head.name_s.to_sym
      end
    end

    def parse_spec(spec, kind)
      return Spec.new(spec.to_s, nil, nil, kind) unless spec.is_a?(::Array)

      ns = spec[0].to_s
      as = nil
      refer = nil
      rest = spec[1..]
      rest.each_slice(2) do |opt, val|
        case opt
        when :as    then as = val.to_s
        when :refer then refer = (val == :all ? :all : val.to_a.map(&:to_s))
        end
      end
      Spec.new(ns, as, refer, kind)
    end

    def list?(form)
      form.is_a?(Cursed::Seq::Cons) || form.is_a?(Cursed::Seq::ISeq)
    end
  end
end

# vim: set sw=2 et cc=80:
