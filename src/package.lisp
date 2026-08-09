(defpackage #:clicklisp
  (:use #:cl)
  (:export
   ;; query compiler
   #:compile-query
   #:sql
   #:*pretty*
   #:sql-error
   #:sql-error-message
   #:sql-error-form
   #:define-sql-function
   #:define-sql-type
   ;; detection rules and named queries
   #:defrule
   #:defquery
   #:register-rule
   #:list-rules
   #:find-rule
   #:rule-sql
   #:rule-name
   #:rule-description
   #:rule-severity
   #:rule-tags
   #:rule-query
   ;; executable UDFs
   #:defudf
   #:find-udf
   #:list-udfs
   #:run-udf
   #:tsv-escape
   #:tsv-unescape
   ;; entry point
   #:main
   #:*version*))

(in-package #:clicklisp)

(defparameter *version*
  #.(let ((here (or *compile-file-truename* *load-truename*)))
      (if here
          (with-open-file (s (merge-pathnames #p"../version.sexp" here))
            (read s))
          "0.0.0-dev"))
  "clicklisp version, single-sourced from version.sexp.")

;;; Query forms from the CLI, rule files and UDF files are read in this
;;; package so that T, NIL and the clause keywords resolve to the standard
;;; symbols, and DEFRULE/DEFUDF are available unqualified.
(defpackage #:clicklisp.forms
  (:use #:cl #:clicklisp))
