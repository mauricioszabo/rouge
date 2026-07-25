# encoding: utf-8

require 'cursed/ruby_ast'

module Cursed
  # Renders a +Cursed::RubyAST+ tree into indented, Rubocop-friendly Ruby
  # source.  All whitespace / layout decisions live here.
  #
  # The core contract of +render(node, level)+ is: the *first* line of the
  # returned string carries no leading indentation (the caller positions it);
  # any continuation lines are indented relative to +level+.
  class PrettyPrinter
    include Cursed::RubyAST

    INDENT = 2
    MAX_WIDTH = 96

    def self.print(node)
      new.render(node, 0)
    end

    # Render a sequence of top-level nodes, separating method/class/module
    # definitions with a blank line.
    def self.print_all(nodes)
      pp = new
      out = +""
      prev_big = false
      nodes.each_with_index do |node, i|
        big = node.is_a?(MethodDef) || node.is_a?(ClassDef) || node.is_a?(ModuleDef)
        out << "\n" if i.positive?
        out << "\n" if i.positive? && (big || prev_big)
        out << pp.render(node, 0)
        prev_big = big
      end
      out << "\n" unless out.empty?
      out
    end

    def render(node, level = 0)
      case node
      when Lit       then node.str
      when ConstPath then node.path
      when Call      then render_call(node, level)
      when Index     then "#{paren(node.recv, level)}[#{render_list(node.args, level)}]"
      when IndexSet
        "#{paren(node.recv, level)}[#{render_list(node.args, level)}] = " \
          "#{render(node.value, level)}"
      when Binop     then render_binop(node, level)
      when Unop      then "#{node.op}#{paren(node.arg, level)}"
      when Assign    then "#{node.target} = #{render(node.value, level)}"
      when Ternary   then render_ternary(node, level)
      when If        then render_if(node, level)
      when Case      then render_case(node, level)
      when ArrayLit  then render_array(node, level)
      when HashLit   then render_hash(node.pairs, level)
      when StrInterp then render_str(node, level)
      when Lambda    then render_lambda(node, level)
      when BlockFn   then render_block_fn(node, level) # standalone (rare)
      when MethodDef then render_method(node, level)
      when ClassDef  then render_class(node, level)
      when ModuleDef then render_module(node, level)
      when Begin     then render_begin(node, level)
      when TryCatch  then render_try(node, level)
      else
        raise "PrettyPrinter: don't know how to render #{node.inspect}"
      end
    end

    private

    def ind(level)
      ' ' * (INDENT * level)
    end

    def render_list(nodes, level)
      nodes.map { |n| render(n, level) }.join(', ')
    end

    # Render a body (array of statement nodes) indented at +level+.  Each node
    # sits on its own line; the last one is the implicit return value.
    def render_body_lines(body, level)
      body.map { |n| ind(level) + render(n, level) }.join("\n")
    end

    # Wrap a header keyword line around an indented body and a closing +end+.
    def wrap(header, body, level)
      inner = render_body_lines(body, level + 1)
      if inner.empty?
        "#{header}\n#{ind(level)}end"
      else
        "#{header}\n#{inner}\n#{ind(level)}end"
      end
    end

    # Parenthesise an expression when it appears as a receiver / operand and
    # could otherwise reassociate.
    def paren(node, level)
      s = render(node, level)
      if node.is_a?(Binop) || node.is_a?(Ternary) || node.is_a?(Unop) ||
         node.is_a?(Lambda) || node.is_a?(Assign)
        "(#{s})"
      else
        s
      end
    end

    def render_call(node, level)
      recv = node.recv ? "#{paren(node.recv, level)}." : ""
      args = node.args.map { |a| render(a, level) }
      args << "&#{render(node.block_pass, level)}" if node.block_pass
      argstr = args.empty? ? "" : "(#{args.join(', ')})"
      base = "#{recv}#{node.name}#{argstr}"
      return base unless node.block

      render_with_block(base, node.block, level)
    end

    def render_with_block(base, block, level)
      pstr = block.params.empty? ? "" : " |#{block.params.join(', ')}|"

      if block.body.size <= 1
        inner = block.body.empty? ? "" : render(block.body.first, level)
        unless inner.include?("\n")
          lead = pstr.empty? ? " " : "#{pstr} "
          oneline = inner.empty? ? "#{base} {#{pstr} }" : "#{base} {#{lead}#{inner} }"
          return oneline if (ind(level).length + oneline.length) <= MAX_WIDTH
        end
      end

      wrap("#{base} do#{pstr}", block.body, level)
    end

    # Operator precedence, used to drop redundant parentheses.
    PRECEDENCE = {
      "||" => 1, "&&" => 2,
      "==" => 3, "!=" => 3,
      "<" => 4, ">" => 4, "<=" => 4, ">=" => 4,
      "|" => 4, "&" => 4, "^" => 4,
      "+" => 5, "-" => 5,
      "*" => 6, "/" => 6, "%" => 6
    }.freeze

    def render_binop(node, level)
      node.args.map { |a| operand(a, node.op, level) }.join(" #{node.op} ")
    end

    def operand(node, parent_op, level)
      s = render(node, level)
      needs =
        case node
        when Binop then (PRECEDENCE[node.op] || 0) < (PRECEDENCE[parent_op] || 0)
        when Ternary, Assign, Lambda then true
        else false
        end
      needs ? "(#{s})" : s
    end

    def render_ternary(node, level)
      "#{paren(node.cond, level)} ? " \
        "#{render(node.then_node, level)} : #{render(node.else_node, level)}"
    end

    def render_if(node, level)
      parts = []
      node.clauses.each_with_index do |(cond, body), i|
        kw = i.zero? ? "if" : "elsif"
        parts << "#{kw} #{render(cond, level)}"
        parts << render_body_lines(body, level + 1) unless body.empty?
      end
      if node.else_body
        parts << "#{ind(level)}else"
        parts << render_body_lines(node.else_body, level + 1) unless node.else_body.empty?
      end
      # Re-stitch: first clause header has no indent; later headers need it.
      out = +""
      node.clauses.each_with_index do |(cond, body), i|
        out << (i.zero? ? "" : "#{ind(level)}")
        out << "#{i.zero? ? 'if' : 'elsif'} #{render(cond, level)}"
        b = render_body_lines(body, level + 1)
        out << "\n#{b}" unless b.empty?
        out << "\n"
      end
      if node.else_body
        out << "#{ind(level)}else"
        b = render_body_lines(node.else_body, level + 1)
        out << "\n#{b}" unless b.empty?
        out << "\n"
      end
      out << "#{ind(level)}end"
      out
    end

    def render_case(node, level)
      out = +"case"
      out << " #{render(node.subject, level)}" if node.subject
      out << "\n"
      node.clauses.each do |test, body|
        out << "#{ind(level)}when #{render(test, level)}"
        b = render_body_lines(body, level + 1)
        out << "\n#{b}" unless b.empty?
        out << "\n"
      end
      if node.else_body
        out << "#{ind(level)}else"
        b = render_body_lines(node.else_body, level + 1)
        out << "\n#{b}" unless b.empty?
        out << "\n"
      end
      out << "#{ind(level)}end"
      out
    end

    def render_array(node, level)
      return "[]" if node.elems.empty?

      inline = "[#{render_list(node.elems, level)}]"
      return inline if !inline.include?("\n") && (ind(level).length + inline.length) <= MAX_WIDTH

      inner = node.elems.map { |e| "#{ind(level + 1)}#{render(e, level + 1)}" }.join(",\n")
      "[\n#{inner}\n#{ind(level)}]"
    end

    def render_hash(pairs, level, braces: true)
      return (braces ? "{}" : "") if pairs.empty?

      rendered = pairs.map { |k, v| render_pair(k, v, level) }
      inline = braces ? "{ #{rendered.join(', ')} }" : rendered.join(', ')
      return inline if !inline.include?("\n") && (ind(level).length + inline.length) <= MAX_WIDTH

      inner = pairs.map { |k, v| "#{ind(level + 1)}#{render_pair(k, v, level + 1)}" }
                   .join(",\n")
      braces ? "{\n#{inner}\n#{ind(level)}}" : inner
    end

    # Use Ruby's +key: value+ shorthand when the key is a plain symbol literal.
    def render_pair(k, v, level)
      ks = render(k, level)
      if k.is_a?(Lit) && ks =~ /\A:[a-zA-Z_]\w*[?!]?\z/
        "#{ks[1..]}: #{render(v, level)}"
      else
        "#{ks} => #{render(v, level)}"
      end
    end

    def render_str(node, level)
      body = node.parts.map do |part|
        if part.is_a?(String)
          part.gsub('\\', '\\\\\\\\').gsub('"', '\\"').gsub("\n", '\n')
        else
          "\#{#{render(part, level)}}"
        end
      end.join
      "\"#{body}\""
    end

    def render_lambda(node, level)
      pstr = node.params.empty? ? "" : "(#{node.params.join(', ')})"
      if node.body.size <= 1
        inner = node.body.empty? ? "" : render(node.body.first, level)
        unless inner.include?("\n")
          oneline = "->#{pstr} { #{inner} }"
          return oneline if (ind(level).length + oneline.length) <= MAX_WIDTH
        end
      end
      header = node.params.empty? ? "lambda do" : "lambda do |#{node.params.join(', ')}|"
      wrap(header, node.body, level)
    end

    def render_block_fn(node, level)
      header = node.params.empty? ? "proc do" : "proc do |#{node.params.join(', ')}|"
      wrap(header, node.body, level)
    end

    def render_method(node, level)
      name = node.singleton ? "self.#{node.name}" : node.name
      header =
        if node.params.empty?
          "def #{name}"
        else
          "def #{name}(#{node.params.join(', ')})"
        end
      wrap(header, node.body, level)
    end

    def render_class(node, level)
      header = node.superclass ? "class #{node.name} < #{node.superclass}" : "class #{node.name}"
      wrap(header, node.body, level)
    end

    def render_module(node, level)
      wrap("module #{node.name}", node.body, level)
    end

    def render_begin(node, level)
      return "nil" if node.body.empty?
      return render(node.body.first, level) if node.body.size == 1

      wrap("begin", node.body, level)
    end

    def render_try(node, level)
      out = +"begin\n"
      out << render_body_lines(node.body, level + 1)
      out << "\n" unless node.body.empty?
      node.rescues.each do |klass, var, body|
        clause = "rescue"
        clause << " #{render(klass, level)}" if klass
        clause << " => #{var}" if var
        out << "#{ind(level)}#{clause}\n"
        b = render_body_lines(body, level + 1)
        out << "#{b}\n" unless b.empty?
      end
      if node.ensure_body
        out << "#{ind(level)}ensure\n"
        b = render_body_lines(node.ensure_body, level + 1)
        out << "#{b}\n" unless b.empty?
      end
      out << "#{ind(level)}end"
      out
    end
  end
end

# vim: set sw=2 et cc=80:
