# encoding: utf-8

module Rouge
  # The tiny runtime that backs *macro bodies* at transpile time.  Macro
  # bodies are themselves transpiled to Ruby and evaluated in-process; the
  # form-builder fns they use (+list+, +concat+, syntax-quote's +seq+, ...)
  # resolve to these methods, which construct reader data (Cons/Symbol).
  module FormRuntime
    module_function

    def list(*xs)
      Rouge::Seq::Cons[*xs]
    end

    def cons(head, tail)
      Rouge::Seq::Cons.new(head, Rouge::Seq.seq(tail) || Rouge::Seq::Empty)
    end

    def concat(*seqs)
      Rouge::Seq::Cons[*seqs.flat_map { |s| to_a(s) }]
    end

    def seq(x)
      Rouge::Seq.seq(x)
    end

    def vector(*xs)
      xs
    end

    def symbol(name)
      Rouge::Symbol[name.to_sym]
    end

    def first(s)
      to_a(s).first
    end

    def rest(s)
      Rouge::Seq::Cons[*to_a(s).drop(1)]
    end

    def apply(fn, *args)
      last = args.pop
      fn.call(*(args + to_a(last)))
    end

    def gensym(prefix = "g__")
      @counter = (@counter || 0) + 1
      Rouge::Symbol[:"#{prefix}#{@counter}__auto__"]
    end

    def to_a(s)
      case s
      when nil then []
      when Rouge::Seq::ISeq then s.to_a
      when ::Array then s
      else
        seqd = Rouge::Seq.seq(s)
        seqd ? seqd.to_a : [s]
      end
    end
  end
end

# vim: set sw=2 et cc=80:
