;;;; Tests for the TabSeparated UDF loop.

(in-package #:clicklisp/test)

(deftest tsv-escaping
  (is= "a\\tb" (tsv-escape (format nil "a~Ab" #\Tab)))
  (is= "a\\nb" (tsv-escape (format nil "a~Ab" #\Newline)))
  (is= "a\\\\b" (tsv-escape "a\\b"))
  (is= "plain" (tsv-escape "plain"))
  (is= (format nil "a~Ab" #\Tab) (tsv-unescape "a\\tb"))
  (is= "a\\b" (tsv-unescape "a\\\\b"))
  ;; round trip
  (let ((nasty (format nil "a~Ab~Ac\\d'e" #\Tab #\Newline)))
    (is= nasty (tsv-unescape (tsv-escape nasty)))))

(defudf test-upcase (s)
  (and s (string-upcase s)))

(defudf test-concat (a b)
  (concatenate 'string (or a "") "|" (or b "")))

(defudf test-boom (s)
  (declare (ignore s))
  (error "boom"))

(defudf test-half (a)
  (/ (parse-integer a) 2))

(defudf test-complex (s)
  (declare (ignore s))
  (complex 1 2))

(defun run-udf-on (name input &rest options)
  (with-output-to-string (out)
    (with-input-from-string (in input)
      (apply #'run-udf name :input in :output out options))))

(deftest udf-row-loop
  (is= (format nil "ABC~%XYZ~%")
       (run-udf-on 'test-upcase (format nil "abc~%xyz~%")))
  ;; two input columns, tab separated
  (is= (format nil "a|b~%")
       (run-udf-on 'test-concat (format nil "a~Ab~%" #\Tab)))
  ;; \N in maps to NIL; NIL out maps to \N
  (is= (format nil "\\N~%")
       (run-udf-on 'test-upcase (format nil "\\N~%")))
  ;; escaped input is unescaped before the function sees it, and the
  ;; result is re-escaped on the way out (the tab survives, escaped)
  (is= (format nil "A\\tB~%")
       (run-udf-on 'test-upcase (format nil "a\\tb~%")))
  ;; a failing row yields \N and does not kill the loop
  (is= (format nil "\\N~%\\N~%")
       (run-udf-on 'test-boom (format nil "x~%y~%")))
  ;; ratio results are rendered as Float64 values, not SQL expressions
  (is= (format nil "1.5~%2~%")
       (run-udf-on 'test-half (format nil "3~%4~%")))
  ;; a result that cannot be rendered (complex number) also yields \N
  ;; instead of killing the process
  (is= (format nil "\\N~%A~%")
       (with-output-to-string (out)
         (with-input-from-string (in (format nil "x~%"))
           (run-udf 'test-complex :input in :output out))
         (with-input-from-string (in (format nil "a~%"))
           (run-udf 'test-upcase :input in :output out))))
  (signals-sql-error (run-udf-on 'no-such-udf (format nil "x~%"))))

(deftest udf-chunked-loop
  (is= (format nil "A~%B~%C~%")
       (run-udf-on 'test-upcase (format nil "2~%a~%b~%1~%c~%") :chunked t))
  (signals-sql-error
   (run-udf-on 'test-upcase (format nil "nonsense~%a~%") :chunked t))
  (signals-sql-error
   (run-udf-on 'test-upcase (format nil "3~%a~%") :chunked t)))

(deftest builtin-udfs
  (let ((entropy-fn (clicklisp::udf-function (find-udf 'entropy)))
        (rot13-fn (clicklisp::udf-function (find-udf 'rot13))))
    (is (= 0.0d0 (funcall entropy-fn "aaaa")))
    (is (< (abs (- 1.0d0 (funcall entropy-fn "abab"))) 1d-9))
    (is (> (funcall entropy-fn "q7x9z2j4k8w1") (funcall entropy-fn "aaaaaaaaaaaa")))
    (is (null (funcall entropy-fn nil)))
    (is= "uryyb" (funcall rot13-fn "hello"))
    (is= "hello" (funcall rot13-fn (funcall rot13-fn "hello")))))

(deftest main-smoke
  ;; exercise the CLI entry through strings, no process spawn needed
  (let ((output (with-output-to-string (out)
                  (let ((*standard-output* out))
                    (main '("version"))))))
    (is (search *version* output)))
  (let ((output (with-output-to-string (out)
                  (let ((*standard-output* out)
                        (*standard-input* (make-string-input-stream
                                           "(select (1))")))
                    (is (zerop (main '("compile"))))))))
    (is= (format nil "SELECT 1~%") output))
  (let ((output (with-output-to-string (out)
                  (let ((*standard-output* out))
                    (is (zerop (main '("compile" "-e" "(select (a) :from t)"))))))))
    (is= (format nil "SELECT a FROM t~%") output))
  ;; two forms are separated by semicolons
  (let ((output (with-output-to-string (out)
                  (let ((*standard-output* out))
                    (main '("compile" "-e" "(select (1)) (select (2))"))))))
    (is= (format nil "SELECT 1;~%SELECT 2;~%") output))
  ;; errors are reported on stderr with a non-zero exit code
  (let* ((errors (make-string-output-stream))
         (code (let ((*error-output* errors))
                 (main '("compile" "-e" "(select (a) :oops 1)")))))
    (is (= 1 code))
    (is (search "unknown clause" (get-output-stream-string errors))))
  ;; #. read-eval is disabled for query input
  (let* ((errors (make-string-output-stream))
         (code (let ((*error-output* errors))
                 (main '("compile" "-e" "(select (#.(+ 1 2)))")))))
    (is (= 1 code))))

(deftest cli-regressions
  ;; float literals survive at Float64 precision through the CLI reader
  (let ((output (with-output-to-string (out)
                  (let ((*standard-output* out))
                    (main '("compile" "-e" "(select (123456789.0))"))))))
    (is (search "1.23456789" output)))
  ;; usage errors exit 2, distinct from query compile errors (1)
  (is (= 2 (let ((*error-output* (make-string-output-stream)))
             (main '("compile" "--bogus")))))
  (is (= 1 (let ((*error-output* (make-string-output-stream)))
             (main '("compile" "-e" "(select (a) :oops 1)")))))
  ;; the rules subcommand is the first positional, wherever flags sit
  (let ((output (with-output-to-string (out)
                  (let ((*standard-output* out))
                    (is (zerop (main '("rules" "--pretty" "sql" "test-rule"))))))))
    (is (search "SELECT count() AS n" output)))
  (is (= 2 (let ((*error-output* (make-string-output-stream)))
             (main '("rules" "list" "extra")))))
  ;; -e and file inputs compile in command-line order; -- ends options
  (let ((path (merge-pathnames "clicklisp-test-order.lisp"
                               (uiop:temporary-directory))))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (write-string "(select (1))" s))
    (unwind-protect
         (progn
           (let ((output (with-output-to-string (out)
                           (let ((*standard-output* out))
                             (main (list "compile" (namestring path)
                                         "-e" "(select (2))"))))))
             (is (equal (format nil "SELECT 1;~%SELECT 2;~%") output)))
           (let ((output (with-output-to-string (out)
                           (let ((*standard-output* out))
                             (main (list "compile" "--" (namestring path)))))))
             (is (equal (format nil "SELECT 1~%") output))))
      (delete-file path))))
