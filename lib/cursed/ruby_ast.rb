# encoding: utf-8

# A small intermediate representation for the Ruby code we emit.  The emitter
# produces trees of these nodes; +Cursed::PrettyPrinter+ turns them into
# indented, Rubocop-friendly Ruby source.  Keeping rendering out of the nodes
# means all formatting decisions live in one place.
module Cursed
  module RubyAST
    class Node; end

    # An already-rendered, single-line Ruby expression (numbers, variable
    # names, +nil+, +true+, constants, etc).
    class Lit < Node
      attr_reader :str
      def initialize(str)
        @str = str.to_s
      end
    end

    # A method/function call.  +recv+ may be nil for a bare call.  +block+ is a
    # BlockFn rendered as a trailing block; +block_pass+ is an expression passed
    # with +&+.
    class Call < Node
      attr_reader :recv, :name, :args, :block, :block_pass
      def initialize(recv, name, args = [], block: nil, block_pass: nil)
        @recv = recv
        @name = name.to_s
        @args = args
        @block = block
        @block_pass = block_pass
      end
    end

    # +recv[k1, k2, ...]+ index access.
    class Index < Node
      attr_reader :recv, :args
      def initialize(recv, args)
        @recv = recv
        @args = args
      end
    end

    # +recv[k] = v+ index assignment.
    class IndexSet < Node
      attr_reader :recv, :args, :value
      def initialize(recv, args, value)
        @recv = recv
        @args = args
        @value = value
      end
    end

    # A chained binary operator, e.g. +a + b + c+ or +a && b+.
    class Binop < Node
      attr_reader :op, :args
      def initialize(op, args)
        @op = op.to_s
        @args = args
      end
    end

    # Unary operators such as +!x+ or +-x+.
    class Unop < Node
      attr_reader :op, :arg
      def initialize(op, arg)
        @op = op.to_s
        @arg = arg
      end
    end

    # +target = value+.  +target+ is a plain string (already munged).
    class Assign < Node
      attr_reader :target, :value
      def initialize(target, value)
        @target = target.to_s
        @value = value
      end
    end

    # +cond ? t : e+.
    class Ternary < Node
      attr_reader :cond, :then_node, :else_node
      def initialize(cond, then_node, else_node)
        @cond = cond
        @then_node = then_node
        @else_node = else_node
      end
    end

    # An +if/elsif/else+ statement.  +clauses+ is an array of [cond, body]
    # pairs; +else_body+ is an array of nodes or nil.
    class If < Node
      attr_reader :clauses, :else_body
      def initialize(clauses, else_body = nil)
        @clauses = clauses
        @else_body = else_body
      end
    end

    # A +case+ statement.  +subject+ may be nil for a bare +case+ /
    # +when cond+ chain.  +clauses+ are [test, body] pairs.
    class Case < Node
      attr_reader :subject, :clauses, :else_body
      def initialize(subject, clauses, else_body = nil)
        @subject = subject
        @clauses = clauses
        @else_body = else_body
      end
    end

    # A literal array, +[a, b, c]+.
    class ArrayLit < Node
      attr_reader :elems
      def initialize(elems)
        @elems = elems
      end
    end

    # A literal hash, +{ k => v }+.  +pairs+ is an array of [key, value].
    class HashLit < Node
      attr_reader :pairs
      def initialize(pairs)
        @pairs = pairs
      end
    end

    # A double-quoted string with interpolation.  +parts+ entries are either
    # String (literal text) or Node (interpolated +#{...}+).
    class StrInterp < Node
      attr_reader :parts
      def initialize(parts)
        @parts = parts
      end
    end

    # A lambda: +->(a, b) { ... }+.
    class Lambda < Node
      attr_reader :params, :body
      def initialize(params, body)
        @params = params
        @body = body
      end
    end

    # A block attached to a call: +{ |a| ... }+ or +do |a| ... end+.
    class BlockFn < Node
      attr_reader :params, :body
      def initialize(params, body)
        @params = params
        @body = body
      end
    end

    # +def name(params) ... end+.  +singleton+ emits +def self.name+.
    class MethodDef < Node
      attr_reader :name, :params, :body, :singleton, :visibility
      def initialize(name, params, body, singleton: false, visibility: nil)
        @name = name.to_s
        @params = params
        @body = body
        @singleton = singleton
        @visibility = visibility
      end
    end

    # +class Name < Super ... end+.
    class ClassDef < Node
      attr_reader :name, :superclass, :body
      def initialize(name, superclass, body)
        @name = name.to_s
        @superclass = superclass
        @body = body
      end
    end

    # +module Name ... end+.
    class ModuleDef < Node
      attr_reader :name, :body
      def initialize(name, body)
        @name = name.to_s
        @body = body
      end
    end

    # +begin ... end+, used when a multi-statement sequence appears where a
    # single expression is expected.
    class Begin < Node
      attr_reader :body
      def initialize(body)
        @body = body
      end
    end

    # +A::B::C+ constant path.
    class ConstPath < Node
      attr_reader :path
      def initialize(path)
        @path = path.to_s
      end
    end

    # +begin ... rescue => e ... ensure ... end+.
    class TryCatch < Node
      attr_reader :body, :rescues, :ensure_body
      # rescues: array of [exception_class_or_nil, var_name_or_nil, body]
      def initialize(body, rescues, ensure_body = nil)
        @body = body
        @rescues = rescues
        @ensure_body = ensure_body
      end
    end
  end
end

# vim: set sw=2 et cc=80:
