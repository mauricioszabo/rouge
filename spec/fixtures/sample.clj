(ns ^{:extends Object :include [Comparable]} my.app.calculator)

(defmacro defop [name op]
  `(defn ~name [a b] (~op a b)))

(defop add +)
(defop mul *)

(defn sum-evens [coll]
  (reduce + (filter even? coll)))

(defn describe [^:map opts]
  (let [label (get opts :label "n")
        total (sum-evens (get opts :nums))]
    (str label ": " total)))

(defn each-doubled [coll ^:block f]
  (.each (map (fn [x] (* x 2)) coll) | f))
