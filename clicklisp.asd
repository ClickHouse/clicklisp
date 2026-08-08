(defsystem "clicklisp"
  :description "S-expression compiler for ClickHouse SQL and single-binary executable UDFs"
  :author "julio@clickhouse.com"
  :version (:read-file-form "version.sexp")
  :serial t
  :components ((:file "src/package")
               (:file "src/names")
               (:file "src/compiler")
               (:file "src/rules")
               (:file "src/udf")
               (:file "src/main"))
  :in-order-to ((test-op (test-op "clicklisp/test"))))

(defsystem "clicklisp/test"
  :description "Test suite for clicklisp"
  :depends-on ("clicklisp")
  :serial t
  :components ((:file "tests/harness")
               (:file "tests/compiler-tests")
               (:file "tests/udf-tests"))
  :perform (test-op (o c)
             (unless (symbol-call '#:clicklisp/test '#:run-tests)
               (error "clicklisp test suite failed"))))
