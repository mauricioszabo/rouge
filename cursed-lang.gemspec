# encoding: utf-8

require File.expand_path('../lib/cursed/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Yuki Izumi", "Maurício Szabo"]
  gem.email         = ["mauricio.szabo@gmail.com"]
  gem.description   = %q{A Clojure-flavoured language that transpiles to readable Ruby.}
  gem.summary       = %q{Clojure -> Ruby source-to-source transpiler (with macros).}
  gem.homepage      = "https://github.com/mauricioszabo/rouge"

  gem.add_development_dependency('rake')
  gem.add_development_dependency('rspec')
  gem.add_development_dependency('rubocop')

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "cursed-lang"
  gem.require_paths = ["lib"]
  gem.version       = Cursed::VERSION
  gem.required_ruby_version = ">= 3.0"
end

# vim: set sw=2 et cc=80:
