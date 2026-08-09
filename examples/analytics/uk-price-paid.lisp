;;;; UK property prices (HM Land Registry, uk.uk_price_paid on the public
;;;; playground): parameterized queries and macro-generated query families.
;;;;
;;;;   clicklisp rules sql --load examples/analytics/uk-price-paid.lisp price-trend \
;;;;     | scripts/play.sh town=LONDON
;;;;
;;;; Town values in the dataset are uppercase (LONDON, YORK, ...).

;; Server-side query parameter + bar() sparkline: one query, any town.
(defquery price-trend
    (:description "Average sale price per year for a town, with sparkline"
     :tags (:uk :trend))
  (select ((as (to-year date) year)
           (as (round (avg price)) avg-price)
           (as (bar (avg price) 0 1500000 20) trend))
    :from uk.uk-price-paid
    :where (= town (param town :string))
    :group-by (year)
    :order-by (year)))

;; Queries are data, so a plain macro stamps out a whole league table
;; family -- one query per property type, no copy-paste.
(defmacro def-price-league (ptype)
  `(defquery ,(intern (format nil "TOP-~A-DISTRICTS" ptype))
       (:description ,(format nil "Priciest districts for ~(~A~) sales since 2020" ptype)
        :tags (:uk :league))
     (select (district (as (round (avg price)) avg-price) (as (count) sales))
       :from uk.uk-price-paid
       :where (and (= type ,(string-downcase (string ptype)))
                   (>= date (to-date "2020-01-01")))
       :group-by (district)
       :having (> sales 100)
       :order-by ((avg-price :desc))
       :limit 10)))

(def-price-league flat)
(def-price-league terraced)
(def-price-league semi-detached)
(def-price-league detached)
(def-price-league other)

;; Parametric aggregates keep their parameters in the function name --
;; (fn "quantile(0.9)" price) -- and LIMIT BY picks the best district
;; per town.
(defquery p90-by-town
    (:description "90th-percentile price and best district per town, 2023+"
     :tags (:uk))
  (select (town district (as (fn "quantile(0.9)" price) p90))
    :from uk.uk-price-paid
    :where (>= date (to-date "2023-01-01"))
    :group-by (town district)
    :order-by ((p90 :desc))
    :limit-by (1 town)
    :limit 20))

;; Window functions have no s-expression syntax (yet); (raw ...) splices
;; verbatim SQL into any expression position when you need one.
(defquery yoy-change
    (:description "Year-over-year national price change (raw window function)"
     :tags (:uk :trend))
  (select ((as (to-year date) year)
           (as (round (avg price)) avg-price)
           (as (raw "round(100 * (avg(price) - lagInFrame(avg(price)) OVER (ORDER BY toYear(date)))
                     / lagInFrame(avg(price)) OVER (ORDER BY toYear(date)), 1)")
               yoy-pct))
    :from uk.uk-price-paid
    :group-by (year)
    :order-by (year)))
