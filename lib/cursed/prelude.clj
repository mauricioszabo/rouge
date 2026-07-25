; The Cursed prelude: core sequence operations expressed with the type-dispatched
; syntax system (defsyntax / defimpl).  Loaded before user code, so an
; unqualified (map ...) / (reduce ...) lowers through these impls and a user can
; extend them for their own types with another (defimpl ...).

; ---- map --------------------------------------------------------------------

(defsyntax map (fn [f coll] (type-of coll)))

(defimpl map :default [^:block f coll]
  `(.map ~coll ~f))

; An OpenStruct has no #map; go through its hash view first.
(defimpl map OpenStruct [^:block f obj]
  `(.. ~obj to-h (map ~f)))

; No statically-known type (more args than the default arity, or via apply):
; one collection behaves like the default; several map in parallel.
(defimpl map :vararg [f & colls]
  (if (= 1 (count colls))
    `(map ~f ~(first colls))
    `(.map (.zip ~(first colls) ~@(rest colls)) ~(as-block f (count colls)))))

; ---- reduce -----------------------------------------------------------------

(defsyntax reduce (fn [f & more] (type-of (last more))))

(defimpl reduce :default
  ([^{:block 2} f coll]      `(.inject ~coll ~f))
  ([^{:block 2} f init coll] `(.inject ~coll ~init ~f)))

; vim: set ft=clojure:
