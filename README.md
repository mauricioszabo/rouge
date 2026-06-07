# Rouge

**A Clojure-flavoured language that transpiles to readable Ruby.**

Rouge reads Clojure-style source and emits clean, indented, Rubocop-friendly
Ruby. It is a **source-to-source transpiler**, not an interpreter — the goal is
to remove boilerplate from Ruby code: write logic (and especially *macros*)
once in Clojure, and let Rouge generate the repetitive Ruby.

> This is a ground-up rewrite. The original Rouge (a Clojure *interpreter* in
> Ruby by Yuki Izumi) lives on in this project's reader, which Rouge reuses.

## Quick start

```bash
# Transpile a file (writes foo.rb next to foo.clj)
bin/rougec foo.clj

# ...or print to stdout
bin/rougec foo.clj --stdout

# Run Rubocop's autocorrect over the output (when rubocop is installed)
bin/rougec foo.clj --rubocop

# Interpret (transpile-then-eval) and print the result
bin/rougec -e '(reduce + (map inc [1 2 3]))'   # => 9

# Interactive REPL (type :ruby to toggle showing emitted Ruby)
bin/rougec --repl
```

From Ruby:

```ruby
require 'rouge'
Rouge.transpile("(defn greet [name] (str \"hi \" name))")
# => "def greet(name)\n  \"hi #{name}\"\nend\n"
Rouge.eval("(+ 1 2)")  # => 3
```

## How it maps

| Rouge                              | Ruby                              |
| ---------------------------------- | -------------------------------- |
| `(ns my.app.user)`                 | `module My; module App; class User` |
| `^{:extends Base}` on the ns       | `class User < Base`              |
| `^{:include [Comparable]}` on ns   | `include Comparable`             |
| `(defn f [a] ...)`                 | `def f(a) ... end`               |
| `(defn ^:self f [] ...)`           | `def self.f ... end`             |
| `(defn- f [] ...)`                 | a `private` method               |
| `(map f coll)`                     | `coll.map { ... }` (last arg!)   |
| `(reduce f init coll)`             | `coll.inject(init) { ... }`      |
| `(filter pred coll)`               | `coll.select { ... }`            |
| `(assoc m :k v)`                   | `m.merge(k: v)`                  |
| `(.method obj a)`                  | `obj.method(a)`                  |
| `(Klass. a)`                       | `Klass.new(a)`                   |

Sequence functions operate on their **last** argument as the Ruby receiver,
and a function argument becomes a Ruby block.

## Block parameters via metadata

Mark a function argument with `^:block` to make it a Ruby block:

```clojure
(defn each-sq [coll ^:block f] (.each coll | f))
```

```ruby
def each_sq(coll, &f)
  coll.each(&f)
end
```

(`| x` inside an interop/call passes `x` as the block, i.e. `&x`.)

## Type hints generate better code

Hint a binding (or argument) so polymorphic operations pick the right Ruby:

```clojure
(let [^:map m {:a 1}
      ^:vector v [1 2 3]]
  (conj v (count (assoc m :b 2))))
```

```ruby
m = { a: 1 }
v = [1, 2, 3]
v + [m.merge({ b: 2 }).size]
```

`conj` becomes `+` on a vector and `merge` on a map; `assoc` becomes `merge`.
Types come from metadata (`^:map`, `^:vector`, `^:set`, `^:string`, `^{:tag X}`)
or are inferred from literals.

## Macros

Macros are the headline feature. A `defmacro` is transpiled to a Ruby lambda,
evaluated **in-process at transpile time**, and called with the unevaluated
argument forms; the form it returns is transpiled in its place. Because
expansion is plain Ruby, macros can read files, the environment, or any data
while expanding.

```clojure
(defmacro defop [name op]
  `(defn ~name [a b] (~op a b)))

(defop add +)
(defop mul *)
```

```ruby
def add(a, b)
  a + b
end

def mul(a, b)
  a * b
end
```

## Inheritance and class mechanics

Inheritance is metadata on the `ns` form; `include` / `extend` / `refine` are
special forms inside the namespace body:

```clojure
(ns ^{:extends ApplicationRecord :include [Comparable]} my.app.user)
(refine String (defn shout [] (.upcase self)))
```

## Interpreter / nREPL

Running Rouge is **transpile-then-eval** (`Rouge::Interpreter`) — there is no
separate evaluator, so a macro defined in a session is immediately usable by
later forms. This is the seed for a future nREPL server, which would simply
delegate eval ops to `Interpreter#eval_str`.

## Development

```bash
gem install rspec        # or: bundle install
rspec                    # run the suite
```

## Authorship

Maintained by [Maurício Szabo](https://github.com/mauricioszabo). The Clojure
reader is reused from the original Rouge by
[Yuki Izumi](https://github.com/kivikakk) and contributors.

## License

The [MIT license](http://opensource.org/licenses/MIT). See `LICENSE`.
