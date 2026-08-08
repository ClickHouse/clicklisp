;;;; ClickHouse executable UDF support: a TabSeparated stdin/stdout row
;;;; loop around functions defined with DEFUDF.
;;;;
;;;; Hot reload: --watch re-LOADs a Lisp file when its write date changes.
;;;; Inside the compiled binary that uses ECL's bytecode compiler, which is
;;;; always in-image — no C toolchain needed in the UDF sandbox.

(in-package #:clicklisp)

;;; ---------------------------------------------------------------------
;;; TabSeparated escaping

(defun tsv-escape (string)
  "Escape STRING for one TabSeparated field."
  (with-output-to-string (out)
    (loop for char across string
          do (case char
               (#\\ (write-string "\\\\" out))
               (#\Tab (write-string "\\t" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (t (write-char char out))))))

(defun tsv-unescape (string)
  "Decode the backslash escapes ClickHouse uses in TabSeparated fields."
  (with-output-to-string (out)
    (loop with i = 0
          with length = (length string)
          while (< i length)
          do (let ((char (char string i)))
               (if (and (char= char #\\) (< (1+ i) length))
                   (let ((next (char string (1+ i))))
                     (write-char (case next
                                   (#\t #\Tab)
                                   (#\n #\Newline)
                                   (#\r #\Return)
                                   (#\b #\Backspace)
                                   (#\f #\Page)
                                   (#\0 (code-char 0))
                                   (#\' #\')
                                   (#\" #\")
                                   (#\\ #\\)
                                   (t next))
                                 out)
                     (incf i 2))
                   (progn
                     (write-char char out)
                     (incf i)))))))

(defun field-value (field)
  "NULL arrives as the two characters \\N; everything else is unescaped."
  (if (string= field "\\N")
      nil
      (tsv-unescape field)))

;;; ---------------------------------------------------------------------
;;; UDF registry

(defstruct (udf (:constructor %make-udf))
  name          ; canonical lowercase string
  function
  documentation)

(defparameter *udfs* (make-hash-table :test 'equal))

(defun udf-key (name)
  (string-downcase (string name)))

(defun register-udf (name function &optional documentation)
  (setf (gethash (udf-key name) *udfs*)
        (%make-udf :name (udf-key name)
                   :function function
                   :documentation documentation))
  name)

(defmacro defudf (name lambda-list &body body)
  "Define an executable UDF. The function receives one string per input
column (NIL for \\N) and returns a value rendered as one output column:
strings verbatim, numbers via the SQL number printer, NIL as \\N, T as
true."
  (let ((documentation (and (stringp (first body)) (rest body) (first body))))
    `(register-udf ',name (lambda ,lambda-list ,@body) ,documentation)))

(defun find-udf (name)
  (gethash (udf-key name) *udfs*))

(defun list-udfs ()
  (let ((udfs '()))
    (maphash (lambda (key udf)
               (declare (ignore key))
               (push udf udfs))
             *udfs*)
    (sort udfs #'string< :key #'udf-name)))

;;; ---------------------------------------------------------------------
;;; Row loop

(defun udf-result-string (value)
  (cond ((null value) "\\N")
        ((eq value t) "true")
        ((stringp value) (tsv-escape value))
        ;; ratios would render as the SQL expression (N / D), which is not
        ;; a parseable TabSeparated value -- emit a Float64 instead
        ((and (rationalp value) (not (integerp value)))
         (float-sql (coerce value 'double-float)))
        ((numberp value) (number-sql value))
        (t (tsv-escape (princ-to-string value)))))

(defun process-line (name line out)
  "Apply the UDF named NAME to one TabSeparated input line. A failing row
(including one whose result cannot be rendered) logs to stderr and yields
\\N rather than killing the process."
  (let ((rendered
          (handler-case
              (let ((udf (find-udf name)))
                (unless udf
                  (error "UDF ~A disappeared after reload" name))
                (udf-result-string
                 (apply (udf-function udf)
                        (mapcar #'field-value (split-string line #\Tab)))))
            (error (e)
              (format *error-output* "clicklisp udf ~A: ~A~%" name e)
              "\\N"))))
    (write-string rendered out)
    (write-char #\Newline out)))

(defun file-stamp (path)
  "Write date plus size: file-write-date alone has one-second resolution,
which would miss a second save within the same second."
  (ignore-errors
    (list (file-write-date path)
          (with-open-file (s path :element-type '(unsigned-byte 8))
            (file-length s)))))

(defun make-watcher (path)
  "Return a thunk that re-LOADs PATH whenever it changes."
  (let ((last (file-stamp path)))
    (lambda ()
      (let ((current (file-stamp path)))
        (when (and current (not (equal current last)))
          (setf last current)
          (handler-case
              ;; anything LOAD prints must stay off *standard-output*:
              ;; that stream is the UDF protocol channel
              (let ((*package* (find-package '#:clicklisp.forms))
                    (*load-verbose* nil)
                    (*load-print* nil)
                    (*standard-output* *error-output*))
                (load path)
                (format *error-output* "clicklisp: reloaded ~A~%" path))
            (error (e)
              (format *error-output* "clicklisp: reload of ~A failed: ~A~%"
                      path e))))))))

(defun run-udf (name &key chunked watch-file
                       (input *standard-input*)
                       (output *standard-output*))
  "Serve the UDF named NAME over stdin/stdout in TabSeparated format.
With CHUNKED (for send_chunk_header = 1 configs), each block is preceded
by a line holding its row count; output is flushed per block. Without it,
output is flushed per row."
  (unless (find-udf name)
    (sql-fail name "unknown UDF ~A; available: ~{~A~^, ~}"
              name (mapcar #'udf-name (list-udfs))))
  (let ((watcher (and watch-file (make-watcher watch-file))))
    (if chunked
        (loop for header = (read-line input nil nil)
              while header
              do (let ((count (handler-case (parse-integer header)
                                (error ()
                                  (sql-fail header
                                            "bad chunk header ~S: expected a row count"
                                            header)))))
                   (when watcher (funcall watcher))
                   (dotimes (i count)
                     (let ((line (read-line input nil nil)))
                       (unless line
                         (sql-fail nil "input ended mid-chunk: expected ~D rows, got ~D"
                                   count i))
                       (process-line name line output)))
                   (finish-output output)))
        (loop for line = (read-line input nil nil)
              while line
              do (when watcher (funcall watcher))
                 (process-line name line output)
                 (finish-output output)))))

;;; ---------------------------------------------------------------------
;;; Built-in demo UDFs

(defun rot13-char (char)
  (cond ((char<= #\a char #\z)
         (code-char (+ (char-code #\a)
                       (mod (+ (- (char-code char) (char-code #\a)) 13) 26))))
        ((char<= #\A char #\Z)
         (code-char (+ (char-code #\A)
                       (mod (+ (- (char-code char) (char-code #\A)) 13) 26))))
        (t char)))

(defudf rot13 (s)
  "ROT13 the input string."
  (and s (map 'string #'rot13-char s)))

(defudf entropy (s)
  "Shannon entropy of the input string in bits per character. Useful for
spotting DGA-style random domains."
  (when s
    (if (zerop (length s))
        0.0d0
        (let ((counts (make-hash-table :test 'eql))
              (length (length s))
              (bits 0.0d0))
          (loop for char across s
                do (incf (gethash char counts 0)))
          (maphash (lambda (char count)
                     (declare (ignore char))
                     ;; coerce before LOG: some ECLs compute the log of a
                     ;; rational at single-float precision
                     (let ((p (coerce (/ count length) 'double-float)))
                       (decf bits (* p (log p 2.0d0)))))
                   counts)
          bits))))
