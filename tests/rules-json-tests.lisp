;;;; Tests for the machine-readable `rules json` output.

(in-package #:clicklisp/test)

(deftest json-string-escaping
  (is= "\"\"" (clicklisp::json-string-literal ""))
  (is= "\"plain ascii 123\"" (clicklisp::json-string-literal "plain ascii 123"))
  (is= "\"a\\\"b\"" (clicklisp::json-string-literal "a\"b"))
  (is= "\"a\\\\b\"" (clicklisp::json-string-literal "a\\b"))
  (is= "\"a\\nb\"" (clicklisp::json-string-literal (format nil "a~%b")))
  (is= "\"a\\tb\"" (clicklisp::json-string-literal (format nil "a~Cb" #\Tab)))
  (is= "\"a\\rb\"" (clicklisp::json-string-literal (format nil "a~Cb" #\Return)))
  ;; control characters below space escape to \u00XX (lowercase hex)
  (is= "\"\\u0001\"" (clicklisp::json-string-literal (string (code-char 1))))
  ;; non-ASCII escapes too, so the output is external-format-proof
  (is= "\"caf\\u00e9\"" (clicklisp::json-string-literal
                         (format nil "caf~C" (code-char #xE9))))
  ;; astral code points become UTF-16 surrogate pairs
  (when (> char-code-limit #x10000)
    (is= "\"\\ud83d\\ude00\""
         (clicklisp::json-string-literal (string (code-char #x1F600))))))

(defrule json-params-rule
    (:description "params fixture" :severity :low :tags (:test))
  (select (a)
    :from t1
    :where (and (> a (param min-lines :uint32))
                (< a (param min-lines :uint32))
                (= town (param "town" :string))
                (> ts (param since :date-time)))))

(defrule json-vector-params-rule
    (:severity :low)
  (select (x) :from t1 :where (in x #((param lo :uint32) (param hi :uint32)))))

(deftest rule-params-extraction
  ;; dedupe by rendered name, first-appearance order, compiler renderings:
  ;; kebab->snake for symbols, strings verbatim, :date-time -> DateTime
  (is= '(("min_lines" . "UInt32") ("town" . "String") ("since" . "DateTime"))
       (clicklisp::rule-params (find-rule "json-params-rule")))
  (is= '() (clicklisp::rule-params (find-rule "test-rule")))
  ;; vector literals compile element-wise, so the walk must enter them
  (is= '(("lo" . "UInt32") ("hi" . "UInt32"))
       (clicklisp::rule-params (find-rule "json-vector-params-rule"))))

(defrule json-full-rule
    (:description "json fixture" :severity :high :tags (:t1110 :ssh))
  (select ((as (count) n)) :from logins :where (= ok (param flag :uint8))))

(deftest rules-json-emission
  (let ((out (with-output-to-string (s)
               (clicklisp::print-rules-json
                (list (find-rule "json-full-rule")) s))))
    (is (search (format nil "\"clicklisp\": \"~A\"" clicklisp:*version*) out))
    (is (search "\"name\": \"json-full-rule\"" out))
    (is (search "\"description\": \"json fixture\"" out))
    (is (search "\"severity\": \"high\"" out))
    (is (search "\"tags\": [\"t1110\", \"ssh\"]" out))
    (is (search "\"params\": [{\"name\": \"flag\", \"type\": \"UInt8\"}]" out))
    (is (search "\"sql\": \"SELECT count() AS n FROM logins WHERE (ok = {flag:UInt8})\"" out))
    (is (search "\"sql_pretty\": \"SELECT count() AS n\\nFROM logins\\nWHERE (ok = {flag:UInt8})\"" out))
    (is (search "\"form\": \"(defrule json-full-rule" out))))

(defquery json-bare-query () (select (1)))

(deftest rules-json-nulls
  (let ((out (with-output-to-string (s)
               (clicklisp::print-rules-json
                (list (find-rule "json-bare-query")) s))))
    (is (search "\"description\": null" out))
    (is (search "\"severity\": null" out))
    (is (search "\"tags\": []" out))
    (is (search "\"params\": []" out))
    (is (search "\"sql\": \"SELECT 1\"" out))))

(deftest rules-json-form-round-trip
  (dolist (name '("json-full-rule" "json-bare-query" "json-params-rule"))
    (let* ((rule (find-rule name))
           (form (let ((*read-eval* nil)
                       (*package* (find-package '#:clicklisp.forms)))
                   (read-from-string (clicklisp::rule-form-text rule)))))
      (is (member (first form) '(defrule defquery)))
      (is= (string-upcase (rule-name rule)) (symbol-name (second form)))
      (is= (rule-sql rule) (compile-query (fourth form))))))
