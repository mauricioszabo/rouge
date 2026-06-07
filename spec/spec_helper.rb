require 'rouge'

RSpec.configure do |config|
  config.order = 'random'
  # symbol_spec/metadata_spec are inherited from the original project and use
  # the legacy `should` syntax.
  config.expect_with(:rspec) { |c| c.syntax = %i[expect should] }
end

# Transpile a Rouge source string to Ruby (fresh env each call).
def transpile(source)
  Rouge::Transpiler.transpile(source)
end

# Transpile a single expression form (no trailing newline) for terse specs.
# A top-level (let ...)/(do ...) becomes a flat statement list, as it would
# inside a method body.
def emit(source)
  emitter = Rouge::Emitter.new
  form = Rouge::Reader.read_all(source).first
  node = emitter.emit(form)
  pp = Rouge::PrettyPrinter.new
  if node.is_a?(Rouge::RubyAST::Begin)
    node.body.map { |n| pp.render(n) }.join("\n")
  else
    pp.render(node)
  end
end

def relative_to_spec(name)
  File.join(File.dirname(File.absolute_path(__FILE__)), name)
end

# vim: set sw=2 et cc=80:
