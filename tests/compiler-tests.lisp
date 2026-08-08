;;;; Tests for the s-expression -> SQL compiler.

(in-package #:clicklisp/test)

(defun cq (form)
  (compile-query form))

(deftest literals
  (is= "SELECT 1" (cq '(select (1))))
  (is= "SELECT -5" (cq '(select (-5))))
  (is= "SELECT 1.5" (cq '(select (1.5))))
  (is= "SELECT (1 / 3)" (cq '(select (1/3))))
  (is= "SELECT 'hello'" (cq '(select ("hello"))))
  (is= "SELECT NULL, true, false" (cq '(select (:null :true :false))))
  (is= "SELECT NULL, true" (cq '(select (nil t))))
  (is= "SELECT [1, 2, 3]" (cq '(select (#(1 2 3)))))
  (is= "SELECT [1, 2]" (cq '(select ((array 1 2)))))
  (is= "SELECT (1, 'a')" (cq '(select ((tuple 1 "a"))))))

(deftest string-escaping
  ;; the classic injection shapes must come out inert
  (is= "SELECT 'O\\'Brien'" (cq '(select ("O'Brien"))))
  (is= "SELECT 'a\\'; DROP TABLE x; --'" (cq '(select ("a'; DROP TABLE x; --"))))
  (is= "SELECT 'back\\\\slash'" (cq '(select ("back\\slash"))))
  (is= (format nil "SELECT 'line~Abreak'" "\\n")
       (cq (list 'select (list (format nil "line~%break"))))))

(deftest identifiers
  (is= "SELECT user FROM events" (cq '(select (user) :from events)))
  (is= "SELECT event_time" (cq '(select (event-time))))
  (is= "SELECT t1.id, t1.*" (cq '(select (t1.id t1.*))))
  ;; reserved words and non-plain names get backticks
  (is= "SELECT `from`" (cq '(select (from))))
  (is= "SELECT `weird name`" (cq '(select (|weird name|))))
  ;; backticks and backslashes inside quoted identifiers are escaped
  (is= "SELECT `a\\`b`" (cq '(select (|a`b|))))
  ;; mixed-case escaped symbols pass through
  (is= "SELECT EventTime" (cq '(select (|EventTime|)))))

(deftest operators
  (is= "SELECT (1 + 2 + 3)" (cq '(select ((+ 1 2 3)))))
  (is= "SELECT (1 - 2)" (cq '(select ((- 1 2)))))
  (is= "SELECT (-x)" (cq '(select ((- x)))))
  (is= "SELECT (a * b)" (cq '(select ((* a b)))))
  (is= "SELECT (a / b)" (cq '(select ((/ a b)))))
  (is= "SELECT (a % b)" (cq '(select ((% a b)))))
  (is= "SELECT (a = 1)" (cq '(select ((= a 1)))))
  (is= "SELECT (a != b)" (cq '(select ((/= a b)))))
  (is= "SELECT (a != b)" (cq '(select ((!= a b)))))
  (is= "SELECT ((1 < x) AND (x < 10))" (cq '(select ((< 1 x 10)))))
  (is= "SELECT ((a = 1) AND (b > 2))" (cq '(select ((and (= a 1) (> b 2))))))
  (is= "SELECT ((a = 1) OR (b = 2))" (cq '(select ((or (= a 1) (= b 2))))))
  (is= "SELECT (NOT a)" (cq '(select ((not a)))))
  (is= "SELECT (a = 1)" (cq '(select ((and (= a 1))))))
  (is= "SELECT true" (cq '(select ((and))))))

(deftest predicates
  (is= "SELECT (user IN ('a', 'b'))" (cq '(select ((in user (list "a" "b"))))))
  (is= "SELECT (user IN (1, 2))" (cq '(select ((in user #(1 2))))))
  (is= "SELECT (user NOT IN ('a'))" (cq '(select ((not-in user (list "a"))))))
  (is= "SELECT (id IN (SELECT id FROM banned))"
       (cq '(select ((in id (select (id) :from banned))))))
  (is= "SELECT (name LIKE '%admin%')" (cq '(select ((like name "%admin%")))))
  (is= "SELECT (name ILIKE 'a%')" (cq '(select ((ilike name "a%")))))
  (is= "SELECT (x BETWEEN 1 AND 10)" (cq '(select ((between x 1 10)))))
  (is= "SELECT (x IS NULL)" (cq '(select ((is-null x)))))
  (is= "SELECT (x IS NOT NULL)" (cq '(select ((is-not-null x))))))

(deftest function-calls
  (is= "SELECT count()" (cq '(select ((count)))))
  (is= "SELECT count(DISTINCT user)" (cq '(select ((count (distinct user))))))
  (is= "SELECT now()" (cq '(select ((now)))))
  (is= "SELECT toStartOfHour(ts)" (cq '(select ((to-start-of-hour ts)))))
  (is= "SELECT countIf((status = 500))" (cq '(select ((count-if (= status 500))))))
  ;; registry-driven irregular names
  (is= "SELECT JSONExtractString(raw, 'user')"
       (cq '(select ((json-extract-string raw "user")))))
  (is= "SELECT toIPv4OrNull(ip)" (cq '(select ((to-ipv4-or-null ip)))))
  (is= "SELECT domainWithoutWWW(url)" (cq '(select ((domain-without-www url)))))
  ;; escaped symbols and fn are verbatim
  (is= "SELECT arrayMap(f, xs)" (cq '(select ((|arrayMap| f xs)))))
  (is= "SELECT toIPv4(ip)" (cq '(select ((fn "toIPv4" ip)))))
  ;; snake_case symbols pass straight through (matches executable UDF names)
  (is= "SELECT clicklisp_entropy(domain)"
       (cq '(select ((clicklisp_entropy domain))))))

(deftest lambdas
  (is= "SELECT arrayMap(x -> (x + 1), xs)"
       (cq '(select ((array-map (lambda (x) (+ x 1)) xs)))))
  (is= "SELECT arrayFilter((x, y) -> (x > y), a, b)"
       (cq '(select ((array-filter (lambda (x y) (> x y)) a b))))))

(deftest conditionals
  (is= "SELECT CASE WHEN (a > 1) THEN 'big' ELSE 'small' END"
       (cq '(select ((case ((> a 1) "big") (:else "small"))))))
  (is= "SELECT CASE status WHEN 200 THEN 'ok' WHEN 500 THEN 'err' END"
       (cq '(select ((case-of status (200 "ok") (500 "err"))))))
  (is= "SELECT if((a > b), a, b)" (cq '(select ((if (> a b) a b))))))

(deftest casts-and-types
  (is= "SELECT CAST(x AS UInt64)" (cq '(select ((cast x :uint64)))))
  (is= "SELECT CAST(x AS String)" (cq '(select ((cast x :string)))))
  (is= "SELECT CAST(x AS Nullable(UInt64))"
       (cq '(select ((cast x (:nullable :uint64))))))
  (is= "SELECT CAST(x AS FixedString(16))"
       (cq '(select ((cast x (:fixed-string 16))))))
  (is= "SELECT CAST(x AS DateTime64(3, 'UTC'))"
       (cq '(select ((cast x (:datetime64 3 "UTC"))))))
  (is= "SELECT CAST(x AS Nullable(UInt64))"
       (cq '(select ((cast x "Nullable(UInt64)"))))))

(deftest misc-expressions
  (is= "SELECT tags[1]" (cq '(select ((aref tags 1)))))
  (is= "SELECT m['k'][2]" (cq '(select ((aref m "k" 2)))))
  (is= "SELECT INTERVAL 1 HOUR" (cq '(select ((interval 1 :hour)))))
  (is= "SELECT INTERVAL 10 MINUTE" (cq '(select ((interval 10 :minutes)))))
  (is= "SELECT (ts > (now() - INTERVAL 1 HOUR))"
       (cq '(select ((> ts (- (now) (interval 1 :hour)))))))
  (is= "SELECT {user_id:UInt64}" (cq '(select ((param user-id :uint64)))))
  (is= "SELECT now() - 1" (cq '(select ((raw "now() - 1")))))
  (is= "SELECT x AS y" (cq '(select ((as x y))))))

(deftest select-clauses
  (is= "SELECT * FROM events" (cq '(select * :from events)))
  (is= "SELECT DISTINCT user FROM events" (cq '(select (:distinct user) :from events)))
  (is= "SELECT count() AS hits FROM events WHERE (status = 500) GROUP BY user HAVING (hits > 10) ORDER BY hits DESC LIMIT 10"
       (cq '(select ((as (count) hits))
             :from events
             :where (= status 500)
             :group-by (user)
             :having (> hits 10)
             :order-by ((hits :desc))
             :limit 10)))
  (is= "SELECT a FROM t ORDER BY a ASC, b DESC NULLS LAST"
       (cq '(select (a) :from t :order-by ((a :asc) (b :desc :nulls-last)))))
  (is= "SELECT a FROM t LIMIT 10 OFFSET 5"
       (cq '(select (a) :from t :limit 10 :offset 5)))
  (is= "SELECT a FROM t LIMIT 3 BY user"
       (cq '(select (a) :from t :limit-by (3 user))))
  (is= "SELECT a FROM t FINAL" (cq '(select (a) :from t :final t)))
  (is= "SELECT a FROM t SAMPLE 0.1" (cq '(select (a) :from t :sample 0.1)))
  (is= "SELECT a FROM t PREWHERE (d = 1) WHERE (b = 2)"
       (cq '(select (a) :from t :prewhere (= d 1) :where (= b 2))))
  (is= "SELECT a FROM t GROUP BY a WITH TOTALS"
       (cq '(select (a) :from t :group-by (a) :with-totals t)))
  (is= "SELECT a FROM t SETTINGS max_threads = 4, use_uncompressed_cache = 1"
       (cq '(select (a) :from t :settings ((max_threads 4)
                                           (use_uncompressed_cache t)))))
  (is= "SELECT a FROM t FORMAT JSONEachRow"
       (cq '(select (a) :from t :format "JSONEachRow"))))

(deftest subqueries-and-joins
  (is= "SELECT count() FROM (SELECT a FROM t1)"
       (cq '(select ((count)) :from (select (a) :from t1))))
  (is= "SELECT a FROM (SELECT a FROM t1) AS sub"
       (cq '(select (a) :from (as (select (a) :from t1) sub))))
  (is= "SELECT a FROM t1 LEFT JOIN t2 ON (t1.id = t2.id)"
       (cq '(select (a) :from t1 :join (:left t2 :on (= t1.id t2.id)))))
  (is= "SELECT a FROM t1 INNER JOIN t2 USING (id, day)"
       (cq '(select (a) :from t1 :join (:inner t2 :using (id day)))))
  (is= "SELECT a FROM t1 CROSS JOIN t2"
       (cq '(select (a) :from t1 :join (:cross t2))))
  (is= "SELECT a FROM t1 LEFT ANTI JOIN t2 ON (t1.id = t2.id) INNER JOIN t3 USING (id)"
       (cq '(select (a) :from t1 :join ((:left-anti t2 :on (= t1.id t2.id))
                                        (:inner t3 :using (id))))))
  (is= "SELECT a FROM t ARRAY JOIN tags"
       (cq '(select (a) :from t :array-join (tags))))
  (is= "SELECT a FROM t LEFT ARRAY JOIN tags AS tag"
       (cq '(select (a) :from t :left-array-join ((as tags tag)))))
  (is= "SELECT EXISTS (SELECT 1)" (cq '(select ((exists (select (1))))))))

(deftest ctes-and-unions
  (is= "WITH total AS (SELECT count() FROM t) SELECT total"
       (cq '(select (total) :with ((total (select ((count)) :from t))))))
  (is= "WITH 5 AS threshold SELECT a FROM t WHERE (a > threshold)"
       (cq '(select (a) :with ((threshold 5)) :from t :where (> a threshold))))
  (is= "SELECT 1 UNION ALL SELECT 2"
       (cq '(union-all (select (1)) (select (2)))))
  (is= "SELECT 1 UNION DISTINCT SELECT 2"
       (cq '(union-distinct (select (1)) (select (2)))))
  ;; union queries are subqueries everywhere selects are
  (is= "WITH cte AS (SELECT 1 UNION ALL SELECT 2) SELECT a FROM cte"
       (cq '(select (a) :with ((cte (union-all (select (1)) (select (2)))))
             :from cte)))
  (is= "SELECT a FROM (SELECT 1 UNION ALL SELECT 2)"
       (cq '(select (a) :from (union-all (select (1)) (select (2))))))
  (is= "SELECT (x IN (SELECT 1 UNION ALL SELECT 2))"
       (cq '(select ((in x (union-all (select (1)) (select (2))))))))
  (is= "SELECT EXISTS (SELECT 1 UNION ALL SELECT 2)"
       (cq '(select ((exists (union-all (select (1)) (select (2)))))))))

(deftest pretty-printing
  (is= (format nil "SELECT a~%FROM t~%WHERE (a = 1)")
       (compile-query '(select (a) :from t :where (= a 1)) :pretty t)))

(deftest sql-macro
  (is= "SELECT 1" (sql (select (1))))
  (is= "SELECT count() AS c FROM events WHERE (ts > (now() - 3600))"
       (sql (select ((as (count) c)) :from events :where (> ts (- (now) 3600))))))

(deftest compile-errors
  (signals-sql-error (cq '(select)))
  (signals-sql-error (cq '(select a :from t)))       ; columns must be a list
  (signals-sql-error (cq '(select (a) :from)))       ; missing clause value
  (signals-sql-error (cq '(select (a) :nonsense 1)))
  (signals-sql-error (cq '(select (a) :where (= a 1) :where (= a 2))))
  (signals-sql-error (cq '(select (a) :from t :join (:sideways t2 :on (= 1 1)))))
  (signals-sql-error (cq '(select ((between x 1)))))
  (signals-sql-error (cq '(select ((lambda x (+ x 1))))))
  (signals-sql-error (cq '(select ((cast x :not-a-type)))))
  (signals-sql-error (cq '(select ((interval 1 :fortnight)))))
  (signals-sql-error (cq '(select ((param "bad name" :uint64)))))
  (signals-sql-error (cq '(select ((raw 42)))))
  (signals-sql-error (cq '(not-a-query)))
  (signals-sql-error (cq 42)))

(defrule test-rule (:description "failed logins" :severity :high :tags (:auth))
  (select ((as (count) n)) :from logins :where (= ok 0)))

(deftest rules
  (let ((rule (find-rule "test-rule")))
    (is (not (null rule)))
    (is (eq :high (rule-severity rule)))
    (is= "SELECT count() AS n FROM logins WHERE (ok = 0)" (rule-sql rule))
    (is (member rule (list-rules))))
  (signals-sql-error
   (clicklisp::register-rule 'bad-severity '(:severity :whatever) '(select (1))))
  (signals-sql-error
   (clicklisp::register-rule 'bad-query '() '(select (a) :oops 1))))

(deftest user-extensions
  (define-sql-function my-weird-fn "MyWeirdFn")
  (is= "SELECT MyWeirdFn(x)" (cq '(select ((my-weird-fn x)))))
  (define-sql-type geo-point "Point")
  (is= "SELECT CAST(x AS Point)" (cq '(select ((cast x :geo-point))))))
