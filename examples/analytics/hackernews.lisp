;;;; Hacker News (hackernews.hackernews on the public playground): text
;;;; search, array lambdas, CTE composition, and a UDF callback.
;;;;
;;;;   clicklisp rules sql --load examples/analytics/hackernews.lisp hype-tracker \
;;;;     | scripts/play.sh term=clojure

;; Track any technology's rise and fall, term bound server-side.
(defquery hype-tracker
    (:description "Monthly HN story mentions of a term, with average score"
     :tags (:hn :text))
  (select ((as (to-start-of-month time) month)
           (as (count) mentions)
           (as (round (avg score) 1) avg-score))
    :from hackernews.hackernews
    :where (and (= type "story")
                (> (position-case-insensitive title (param term :string)) 0))
    :group-by (month)
    :order-by (month)))

;; The playground table materializes a words Array(String) column; Lisp
;; lambdas are ClickHouse lambdas, and ARRAY JOIN unnests the result.
(defquery long-words
    (:description "Most common >8-char words in stories since 2024"
     :tags (:hn :arrays))
  (select ((as word w) (as (count) c))
    :from hackernews.hackernews
    :array-join ((as (array-filter (lambda (w) (> (length w) 8)) words) word))
    :where (and (= type "story") (>= time (to-date "2024-01-01")))
    :group-by (word)
    :order-by ((c :desc))
    :limit 25))

;; A CTE defined once, consumed via IN -- named subqueries compose.
;; (`by` is a reserved word; the compiler backticks it automatically.)
(defquery prolific-authors
    (:description "Average story score of authors with >200 submissions"
     :tags (:hn))
  (select (by (as (round (avg score) 1) avg-score) (as (count) stories))
    :with ((prolific (select (by)
                       :from hackernews.hackernews
                       :where (= type "story")
                       :group-by (by)
                       :having (> (count) 200))))
    :from hackernews.hackernews
    :where (and (= type "story") (in by prolific))
    :group-by (by)
    :order-by ((avg-score :desc))
    :limit 20))

;; LOCAL ONLY: calls the clicklisp_shout executable UDF from
;; examples/udfs/text.lisp -- see the README for loading a local HN table
;; and wiring the UDF in. Executable UDF names must be written snake_case:
;; a kebab-case (clicklisp-shout ...) would compile to clicklispShout(...).
(defquery shouting-titles
    (:description "High-scoring stories with ALL-CAPS-heavy titles (needs the clicklisp_shout UDF)"
     :tags (:hn :udf))
  (select (title score (as (clicklisp_shout title) shout))
    :from hackernews
    :where (and (= type "story") (> score 100) (> (clicklisp_shout title) 0.5))
    :order-by ((shout :desc))
    :limit 25))
