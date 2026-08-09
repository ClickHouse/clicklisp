;;;; The s-expression -> ClickHouse SQL compiler.
;;;;
;;;; Query forms are plain data: operators and clause names are matched by
;;;; symbol name, not by package, so forms can be read or constructed
;;;; anywhere. Every infix expression is parenthesized, which sidesteps
;;;; precedence entirely.

(in-package #:clicklisp)

(defparameter *pretty* nil
  "When true, top-level clauses are separated by newlines.")

;;; ---------------------------------------------------------------------
;;; Form helpers

(defun head-name (form)
  (and (consp form)
       (symbolp (first form))
       (first form)
       (symbol-name (first form))))

(defun head-name-p (form name)
  (let ((head (head-name form)))
    (and head (string-equal head name))))

(defun select-form-p (form)
  (head-name-p form "SELECT"))

(defun query-form-p (form)
  "A form that stands for a whole query: select or a union of queries."
  (or (select-form-p form)
      (head-name-p form "UNION-ALL")
      (head-name-p form "UNION-DISTINCT")))

(defun expect-args (form n)
  (let ((actual (length (rest form))))
    (unless (= actual n)
      (sql-fail form "~(~A~) expects ~D argument~:P, got ~D"
                (first form) n actual))))

(defun expect-min-args (form n)
  (unless (>= (length (rest form)) n)
    (sql-fail form "~(~A~) expects at least ~D argument~:P" (first form) n)))

;;; ---------------------------------------------------------------------
;;; Expressions

(defparameter *special-forms* (make-hash-table :test 'equal))

(defmacro define-sql-special ((&rest names) (form-var) &body body)
  `(let ((handler (lambda (,form-var)
                    (declare (ignorable ,form-var))
                    ,@body)))
     (dolist (name ',names)
       (setf (gethash (string-upcase name) *special-forms*) handler))))

(defun expr-sql (form)
  (cond
    ((null form) "NULL")
    ((eq form t) "true")
    ((numberp form) (number-sql form))
    ((stringp form) (string-literal form))
    ((characterp form) (string-literal (string form)))
    ((keywordp form)
     (let ((name (symbol-name form)))
       (cond ((string-equal name "NULL") "NULL")
             ((string-equal name "TRUE") "true")
             ((string-equal name "FALSE") "false")
             ((string= name "*") "*")
             (t (identifier-sql form)))))
    ((symbolp form)
     (if (string= (symbol-name form) "*")
         "*"
         (identifier-sql form)))
    ((and (vectorp form) (not (stringp form)))
     (format nil "[~{~A~^, ~}]" (map 'list #'expr-sql form)))
    ((consp form) (call-sql form))
    (t (sql-fail form "cannot compile ~S of type ~S" form (type-of form)))))

(defun call-sql (form)
  (let ((head (first form)))
    (cond
      ((symbolp head)
       (let ((handler (gethash (string-upcase (symbol-name head))
                               *special-forms*)))
         (if handler
             (funcall handler form)
             (generic-call-sql form))))
      ((stringp head) (generic-call-sql form))
      (t (sql-fail form "expression head must be a symbol or string")))))

(defun generic-call-sql (form)
  (format nil "~A(~{~A~^, ~})"
          (function-name-sql (first form))
          (mapcar #'expr-sql (rest form))))

(defun infix-sql (op args)
  (format nil "(~A)"
          (join-strings (mapcar #'expr-sql args)
                        (format nil " ~A " op))))

;;; Arithmetic

(define-sql-special ("+") (form)
  (expect-min-args form 1)
  (if (= 1 (length (rest form)))
      (expr-sql (second form))
      (infix-sql "+" (rest form))))

(define-sql-special ("-") (form)
  (expect-min-args form 1)
  (if (= 1 (length (rest form)))
      (format nil "(-~A)" (expr-sql (second form)))
      (infix-sql "-" (rest form))))

(define-sql-special ("*") (form)
  (expect-min-args form 2)
  (infix-sql "*" (rest form)))

(define-sql-special ("/") (form)
  (expect-min-args form 2)
  (infix-sql "/" (rest form)))

(define-sql-special ("%") (form)
  (expect-args form 2)
  (infix-sql "%" (rest form)))

;;; Logic

(define-sql-special ("and") (form)
  (let ((args (rest form)))
    (case (length args)
      (0 "true")
      (1 (expr-sql (first args)))
      (t (infix-sql "AND" args)))))

(define-sql-special ("or") (form)
  (let ((args (rest form)))
    (case (length args)
      (0 "false")
      (1 (expr-sql (first args)))
      (t (infix-sql "OR" args)))))

(define-sql-special ("not") (form)
  (expect-args form 1)
  (format nil "(NOT ~A)" (expr-sql (second form))))

;;; Comparisons, chained like Lisp: (< a b c) => ((a < b) AND (b < c))

(defun comparison-sql (op form)
  (expect-min-args form 2)
  (let* ((args (mapcar #'expr-sql (rest form)))
         (pairs (loop for (a b) on args
                      while b
                      collect (format nil "(~A ~A ~A)" a op b))))
    (if (rest pairs)
        (format nil "(~{~A~^ AND ~})" pairs)
        (first pairs))))

(define-sql-special ("=") (form) (comparison-sql "=" form))
(define-sql-special ("!=" "/=" "<>") (form) (comparison-sql "!=" form))
(define-sql-special ("<") (form) (comparison-sql "<" form))
(define-sql-special ("<=") (form) (comparison-sql "<=" form))
(define-sql-special (">") (form) (comparison-sql ">" form))
(define-sql-special (">=") (form) (comparison-sql ">=" form))

;;; Membership

(defun set-sql (form)
  "Render the right-hand side of IN: a literal set, a subquery, or any
expression (e.g. a table identifier)."
  (cond
    ((query-form-p form)
     (format nil "(~A)" (query-sql form)))
    ((or (head-name-p form "LIST") (head-name-p form "TUPLE"))
     (progn
       (expect-min-args form 1)
       (format nil "(~{~A~^, ~})" (mapcar #'expr-sql (rest form)))))
    ((and (vectorp form) (not (stringp form)))
     (format nil "(~{~A~^, ~})" (map 'list #'expr-sql form)))
    (t (expr-sql form))))

(defun membership-sql (op form)
  (expect-args form 2)
  (format nil "(~A ~A ~A)"
          (expr-sql (second form)) op (set-sql (third form))))

(define-sql-special ("in") (form) (membership-sql "IN" form))
(define-sql-special ("not-in") (form) (membership-sql "NOT IN" form))
(define-sql-special ("global-in") (form) (membership-sql "GLOBAL IN" form))
(define-sql-special ("global-not-in") (form) (membership-sql "GLOBAL NOT IN" form))

;;; Pattern matching

(defun binary-op-sql (op form)
  (expect-args form 2)
  (format nil "(~A ~A ~A)"
          (expr-sql (second form)) op (expr-sql (third form))))

(define-sql-special ("like") (form) (binary-op-sql "LIKE" form))
(define-sql-special ("not-like") (form) (binary-op-sql "NOT LIKE" form))
(define-sql-special ("ilike") (form) (binary-op-sql "ILIKE" form))
(define-sql-special ("not-ilike") (form) (binary-op-sql "NOT ILIKE" form))

;;; Ranges and NULL tests

(define-sql-special ("between") (form)
  (expect-args form 3)
  (format nil "(~A BETWEEN ~A AND ~A)"
          (expr-sql (second form))
          (expr-sql (third form))
          (expr-sql (fourth form))))

(define-sql-special ("not-between") (form)
  (expect-args form 3)
  (format nil "(~A NOT BETWEEN ~A AND ~A)"
          (expr-sql (second form))
          (expr-sql (third form))
          (expr-sql (fourth form))))

(define-sql-special ("is-null") (form)
  (expect-args form 1)
  (format nil "(~A IS NULL)" (expr-sql (second form))))

(define-sql-special ("is-not-null") (form)
  (expect-args form 1)
  (format nil "(~A IS NOT NULL)" (expr-sql (second form))))

;;; Conditionals

(defun else-clause-p (test)
  (and (symbolp test)
       (member (symbol-name test) '("ELSE" "OTHERWISE" "T")
               :test #'string-equal)))

(defun case-clauses-sql (clauses form)
  (let ((whens '())
        (else nil))
    (dolist (clause clauses)
      (unless (and (consp clause) (= 2 (length clause)))
        (sql-fail form "case clause must be (test result), got ~S" clause))
      (destructuring-bind (test result) clause
        (if (else-clause-p test)
            (setf else (expr-sql result))
            (push (format nil "WHEN ~A THEN ~A"
                          (expr-sql test) (expr-sql result))
                  whens))))
    (unless whens
      (sql-fail form "case needs at least one non-else clause"))
    (values (nreverse whens) else)))

(define-sql-special ("case") (form)
  (expect-min-args form 1)
  (multiple-value-bind (whens else) (case-clauses-sql (rest form) form)
    (format nil "CASE ~{~A ~}~@[ELSE ~A ~]END" whens else)))

(define-sql-special ("case-of") (form)
  (expect-min-args form 2)
  (multiple-value-bind (whens else) (case-clauses-sql (cddr form) form)
    (format nil "CASE ~A ~{~A ~}~@[ELSE ~A ~]END"
            (expr-sql (second form)) whens else)))

;;; Lambdas: (lambda (x) body) => x -> body

(define-sql-special ("lambda") (form)
  (expect-args form 2)
  (destructuring-bind (params body) (rest form)
    (unless (and (consp params) (every #'symbolp params))
      (sql-fail form "lambda parameters must be a list of symbols"))
    (let ((rendered (mapcar #'identifier-sql params)))
      (if (rest rendered)
          (format nil "(~{~A~^, ~}) -> ~A" rendered (expr-sql body))
          (format nil "~A -> ~A" (first rendered) (expr-sql body))))))

;;; Aliases, casts, containers

(define-sql-special ("as") (form)
  (expect-args form 2)
  (format nil "~A AS ~A"
          (expr-sql (second form))
          (identifier-sql (third form))))

(define-sql-special ("cast") (form)
  (expect-args form 2)
  (format nil "CAST(~A AS ~A)"
          (expr-sql (second form))
          (type-sql (third form))))

(define-sql-special ("tuple" "list") (form)
  (expect-min-args form 1)
  (format nil "(~{~A~^, ~})" (mapcar #'expr-sql (rest form))))

(define-sql-special ("array") (form)
  (format nil "[~{~A~^, ~}]" (mapcar #'expr-sql (rest form))))

(define-sql-special ("aref" "at") (form)
  (expect-min-args form 2)
  (format nil "~A~{[~A]~}"
          (expr-sql (second form))
          (mapcar #'expr-sql (cddr form))))

(define-sql-special ("distinct") (form)
  (expect-min-args form 1)
  (format nil "DISTINCT ~{~A~^, ~}" (mapcar #'expr-sql (rest form))))

;;; Intervals

(defparameter +interval-units+
  '("SECOND" "MINUTE" "HOUR" "DAY" "WEEK" "MONTH" "QUARTER" "YEAR"
    "NANOSECOND" "MICROSECOND" "MILLISECOND"))

(define-sql-special ("interval") (form)
  (expect-args form 2)
  (destructuring-bind (amount unit) (rest form)
    (unless (symbolp unit)
      (sql-fail form "interval unit must be a symbol like :hour"))
    (let* ((name (string-upcase (symbol-name unit)))
           ;; accept plural spellings: :minutes => MINUTE
           (singular (if (and (> (length name) 1)
                              (char= (char name (1- (length name))) #\S))
                         (subseq name 0 (1- (length name)))
                         name)))
      (unless (member singular +interval-units+ :test #'string=)
        (sql-fail form "unknown interval unit ~A" unit))
      (format nil "INTERVAL ~A ~A" (expr-sql amount) singular))))

;;; Query parameters: (param user-id :uint64) => {user_id:UInt64}

(define-sql-special ("param") (form)
  (expect-args form 2)
  (destructuring-bind (name type) (rest form)
    (let ((rendered (etypecase name
                      (string name)
                      (symbol (substitute #\_ #\- (symbol-sql-name name))))))
      (unless (and (plusp (length rendered))
                   (every #'plain-identifier-char-p rendered)
                   (not (char<= #\0 (char rendered 0) #\9)))
        (sql-fail form "bad parameter name ~S" name))
      (format nil "{~A:~A}" rendered (type-sql type)))))

;;; Escape hatches

(define-sql-special ("raw") (form)
  (expect-args form 1)
  (let ((sql (second form)))
    (unless (stringp sql)
      (sql-fail form "raw expects a string"))
    sql))

(define-sql-special ("fn") (form)
  (expect-min-args form 1)
  (let ((name (second form)))
    (unless (stringp name)
      (sql-fail form "fn expects a verbatim function name string"))
    (format nil "~A(~{~A~^, ~})" name (mapcar #'expr-sql (cddr form)))))

;;; Subqueries in expression position

(define-sql-special ("select") (form)
  (format nil "(~A)" (select-sql form)))

(define-sql-special ("exists") (form)
  (expect-args form 1)
  (unless (query-form-p (second form))
    (sql-fail form "exists expects a (select ...) or union form"))
  (format nil "EXISTS (~A)" (query-sql (second form))))

;;; ---------------------------------------------------------------------
;;; SELECT statements

(defun table-ref-final-p (spec)
  "True when SPEC already renders a FINAL modifier."
  (or (head-name-p spec "FINAL")
      (and (head-name-p spec "AS")
           (head-name-p (second spec) "FINAL"))))

(defun table-ref-sql (spec)
  (cond
    ((and spec (symbolp spec)) (identifier-sql spec))
    ((stringp spec) (identifier-sql spec))
    ((query-form-p spec) (format nil "(~A)" (query-sql spec)))
    ((head-name-p spec "AS")
     (progn
       (expect-args spec 2)
       ;; ClickHouse puts FINAL after the alias: t AS x FINAL
       (let ((table (second spec)))
         (when (head-name-p table "AS")
           (sql-fail spec "table reference ~S is aliased twice" spec))
         (if (head-name-p table "FINAL")
             (progn
               (expect-args table 1)
               (when (or (head-name-p (second table) "AS")
                         (head-name-p (second table) "FINAL"))
                 (sql-fail spec "bad table reference ~S: FINAL takes a plain table or subquery here" spec))
               (format nil "~A AS ~A FINAL"
                       (table-ref-sql (second table))
                       (identifier-sql (third spec))))
             (format nil "~A AS ~A"
                     (table-ref-sql table)
                     (identifier-sql (third spec)))))))
    ((head-name-p spec "FINAL")
     (progn
       (expect-args spec 1)
       (when (table-ref-final-p (second spec))
         (sql-fail spec "redundant FINAL in ~S" spec))
       (format nil "~A FINAL" (table-ref-sql (second spec)))))
    (t (sql-fail spec "bad table reference ~S" spec))))

(defparameter +join-kinds+
  '("INNER" "LEFT" "RIGHT" "FULL" "CROSS" "ANY" "ALL" "ASOF" "PASTE"
    "LEFT-OUTER" "RIGHT-OUTER" "FULL-OUTER"
    "LEFT-SEMI" "RIGHT-SEMI" "LEFT-ANTI" "RIGHT-ANTI"
    "LEFT-ANY" "RIGHT-ANY" "LEFT-ASOF"))

(defun join-sql (spec)
  (unless (and (consp spec)
               (keywordp (first spec))
               (>= (length spec) 2))
    (sql-fail spec "join spec must look like (:left table :on expr)"))
  (let ((kind (symbol-name (first spec))))
    (unless (member kind +join-kinds+ :test #'string-equal)
      (sql-fail spec "unknown join kind ~S" (first spec)))
    (destructuring-bind (table &key on using) (rest spec)
      (when (and on using)
        (sql-fail spec "join takes :on or :using, not both"))
      (unless (or on using (string-equal kind "CROSS") (string-equal kind "PASTE"))
        (sql-fail spec "join needs an :on expression or :using columns"))
      (format nil "~A JOIN ~A~@[ ON ~A~]~@[ USING (~{~A~^, ~})~]"
              (substitute #\Space #\- (string-upcase kind))
              (table-ref-sql table)
              (and on (expr-sql on))
              (and using
                   (mapcar #'identifier-sql
                           (if (listp using) using (list using))))))))

(defun with-item-sql (item)
  (unless (and (consp item) (= 2 (length item)))
    (sql-fail item "with item must be (name expr) or (name (select ...))"))
  (destructuring-bind (name expr) item
    (if (query-form-p expr)
        (format nil "~A AS (~A)" (identifier-sql name) (query-sql expr))
        (format nil "~A AS ~A" (expr-sql expr) (identifier-sql name)))))

(defun order-item-sql (item)
  (let ((expr item)
        (modifiers '()))
    (when (and (consp item)
               (rest item)
               (every #'keywordp (rest item)))
      (setf expr (first item)
            modifiers (rest item)))
    (format nil "~A~{ ~A~}"
            (expr-sql expr)
            (mapcar (lambda (modifier)
                      (let ((name (symbol-name modifier)))
                        (cond ((string-equal name "ASC") "ASC")
                              ((string-equal name "DESC") "DESC")
                              ((string-equal name "NULLS-FIRST") "NULLS FIRST")
                              ((string-equal name "NULLS-LAST") "NULLS LAST")
                              (t (sql-fail item "unknown order modifier ~S"
                                           modifier)))))
                    modifiers))))

(defun setting-sql (item)
  (unless (and (consp item) (= 2 (length item)))
    (sql-fail item "setting must be (name value)"))
  (destructuring-bind (name value) item
    (format nil "~A = ~A"
            (identifier-sql name)
            (cond ((numberp value) (number-sql value))
                  ((stringp value) (string-literal value))
                  ((eq value t) "1")
                  ((null value) "0")
                  (t (sql-fail item "bad setting value ~S" value))))))

(defun select-columns-sql (columns form)
  (cond
    ((and columns (symbolp columns) (string= (symbol-name columns) "*"))
     "*")
    ((consp columns)
     (let ((distinct nil)
           (cols columns))
       (when (and (keywordp (first columns))
                  (string-equal (symbol-name (first columns)) "DISTINCT"))
         (setf distinct t
               cols (rest columns)))
       (unless cols
         (sql-fail form "empty column list"))
       (format nil "~:[~;DISTINCT ~]~{~A~^, ~}"
               distinct (mapcar #'expr-sql cols))))
    (t (sql-fail form
                 "the column list must be a list of expressions or *, got ~S"
                 columns))))

(defparameter +select-clauses+
  '("WITH" "FROM" "FINAL" "SAMPLE" "JOIN" "ARRAY-JOIN" "LEFT-ARRAY-JOIN"
    "PREWHERE" "WHERE" "GROUP-BY" "WITH-TOTALS" "WITH-ROLLUP" "WITH-CUBE"
    "HAVING" "ORDER-BY" "LIMIT" "OFFSET" "LIMIT-BY" "SETTINGS" "FORMAT"))

(defun parse-select-clauses (clauses form)
  (let ((table (make-hash-table :test 'equal)))
    (loop for tail on clauses by #'cddr
          do (let ((key (first tail)))
               (unless (keywordp key)
                 (sql-fail form "expected a keyword clause name, got ~S" key))
               (when (null (rest tail))
                 (sql-fail form "clause ~S is missing a value" key))
               (let ((name (string-upcase (symbol-name key))))
                 (unless (member name +select-clauses+ :test #'string=)
                   (sql-fail form "unknown clause ~S" key))
                 (when (nth-value 1 (gethash name table))
                   (sql-fail form "duplicate clause ~S" key))
                 (setf (gethash name table) (second tail)))))
    table))

(defun select-sql (form)
  (unless (and (consp form) (>= (length form) 2))
    (sql-fail form "select needs a column list"))
  (let* ((clauses (parse-select-clauses (cddr form) form))
         (parts '()))
    (flet ((clause (name) (gethash name clauses))
           (clause-p (name) (nth-value 1 (gethash name clauses)))
           (emit (string) (push string parts)))
      (when (clause-p "WITH")
        (let ((items (clause "WITH")))
          (unless (consp items)
            (sql-fail form ":with expects a list of (name expr) items"))
          (emit (format nil "WITH ~{~A~^, ~}"
                        (mapcar #'with-item-sql items)))))
      (emit (format nil "SELECT ~A" (select-columns-sql (second form) form)))
      (when (clause-p "FROM")
        (when (and (clause "FINAL") (table-ref-final-p (clause "FROM")))
          (sql-fail form ":final t duplicates the FINAL already in ~S"
                    (clause "FROM")))
        (emit (format nil "FROM ~A~:[~; FINAL~]~@[ SAMPLE ~A~]"
                      (table-ref-sql (clause "FROM"))
                      (clause "FINAL")
                      (and (clause-p "SAMPLE")
                           (expr-sql (clause "SAMPLE"))))))
      (when (and (clause-p "FINAL") (not (clause-p "FROM")))
        (sql-fail form ":final requires :from"))
      (when (and (clause-p "SAMPLE") (not (clause-p "FROM")))
        (sql-fail form ":sample requires :from"))
      (when (clause-p "JOIN")
        (let* ((value (clause "JOIN"))
               (specs (if (and (consp value) (keywordp (first value)))
                          (list value)
                          value)))
          (unless (consp specs)
            (sql-fail form ":join expects a join spec or a list of them"))
          (dolist (spec specs)
            (emit (join-sql spec)))))
      (dolist (entry '(("ARRAY-JOIN" . "ARRAY JOIN")
                       ("LEFT-ARRAY-JOIN" . "LEFT ARRAY JOIN")))
        (when (clause-p (car entry))
          (let ((items (clause (car entry))))
            (unless (consp items)
              (sql-fail form ":~(~A~) expects a list of expressions" (car entry)))
            (emit (format nil "~A ~{~A~^, ~}"
                          (cdr entry) (mapcar #'expr-sql items))))))
      (when (clause-p "PREWHERE")
        (emit (format nil "PREWHERE ~A" (expr-sql (clause "PREWHERE")))))
      (when (clause-p "WHERE")
        (emit (format nil "WHERE ~A" (expr-sql (clause "WHERE")))))
      (when (clause-p "GROUP-BY")
        (let ((items (clause "GROUP-BY")))
          (unless (consp items)
            (sql-fail form ":group-by expects a list of expressions"))
          (emit (format nil "GROUP BY ~{~A~^, ~}~:[~; WITH TOTALS~]~:[~; WITH ROLLUP~]~:[~; WITH CUBE~]"
                        (mapcar #'expr-sql items)
                        (clause "WITH-TOTALS")
                        (clause "WITH-ROLLUP")
                        (clause "WITH-CUBE")))))
      (dolist (name '("WITH-TOTALS" "WITH-ROLLUP" "WITH-CUBE"))
        (when (and (clause-p name) (not (clause-p "GROUP-BY")))
          (sql-fail form ":~(~A~) requires :group-by" name)))
      (when (clause-p "HAVING")
        (emit (format nil "HAVING ~A" (expr-sql (clause "HAVING")))))
      (when (clause-p "ORDER-BY")
        (let ((items (clause "ORDER-BY")))
          (unless (consp items)
            (sql-fail form ":order-by expects a list of order items"))
          (emit (format nil "ORDER BY ~{~A~^, ~}"
                        (mapcar #'order-item-sql items)))))
      (when (clause-p "LIMIT-BY")
        (let ((value (clause "LIMIT-BY")))
          (unless (and (consp value) (>= (length value) 2))
            (sql-fail form ":limit-by expects (count expr ...)"))
          (emit (format nil "LIMIT ~A BY ~{~A~^, ~}"
                        (expr-sql (first value))
                        (mapcar #'expr-sql (rest value))))))
      (when (clause-p "LIMIT")
        (emit (format nil "LIMIT ~A" (expr-sql (clause "LIMIT")))))
      (when (clause-p "OFFSET")
        (emit (format nil "OFFSET ~A" (expr-sql (clause "OFFSET")))))
      (when (clause-p "SETTINGS")
        (let ((items (clause "SETTINGS")))
          (unless (consp items)
            (sql-fail form ":settings expects a list of (name value) items"))
          (emit (format nil "SETTINGS ~{~A~^, ~}"
                        (mapcar #'setting-sql items)))))
      (when (clause-p "FORMAT")
        (let ((value (clause "FORMAT")))
          (unless (and (stringp value) (plusp (length value)))
            (sql-fail form ":format expects a verbatim format name string like \"JSONEachRow\""))
          (emit (format nil "FORMAT ~A" value)))))
    (join-strings (nreverse parts)
                  (if *pretty* (string #\Newline) " "))))

;;; ---------------------------------------------------------------------
;;; Top-level queries

(defun union-sql (form keyword)
  (expect-min-args form 2)
  (join-strings (mapcar #'query-sql (rest form))
                (if *pretty*
                    (format nil "~%~A~%" keyword)
                    (format nil " ~A " keyword))))

(defun query-sql (form)
  (cond
    ((select-form-p form) (select-sql form))
    ((head-name-p form "UNION-ALL") (union-sql form "UNION ALL"))
    ((head-name-p form "UNION-DISTINCT") (union-sql form "UNION DISTINCT"))
    (t (sql-fail form "expected a query form: (select ...), (union-all ...) or (union-distinct ...)"))))

(defun compile-query (form &key ((:pretty *pretty*) *pretty*))
  "Compile a query form to a ClickHouse SQL string."
  (query-sql form))

(defmacro sql (form)
  "Compile FORM to SQL at macroexpansion time, yielding a literal string."
  (compile-query form))
