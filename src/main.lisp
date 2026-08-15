;;;; Command-line entry point.

(in-package #:clicklisp)

;;; ---------------------------------------------------------------------
;;; Portability shims (the compiled binary avoids depending on UIOP)

(defun command-line-arguments ()
  #+ecl (rest (ext:command-args))
  #-ecl (uiop:command-line-arguments))

;;; ---------------------------------------------------------------------
;;; Reading query forms

(defun read-forms-from-stream (stream)
  (let ((*read-eval* nil)
        (*package* (find-package '#:clicklisp.forms))
        ;; read float literals at Float64 precision, matching ClickHouse
        (*read-default-float-format* 'double-float)
        (eof '#:eof))
    (loop for form = (read stream nil eof)
          until (eq form eof)
          collect form)))

(defun read-forms-from-string (string)
  (with-input-from-string (stream string)
    (read-forms-from-stream stream)))

(defun read-forms-from-file (path)
  (with-open-file (stream path)
    (read-forms-from-stream stream)))

(defun load-user-file (path)
  "Load a Lisp file (rules, UDFs) in the forms package."
  (let ((*package* (find-package '#:clicklisp.forms))
        (*read-default-float-format* 'double-float)
        (*load-verbose* nil)
        (*load-print* nil))
    (load path)))

;;; Bad invocations exit 2; bad input (queries that do not compile) exits 1.
(define-condition usage-error (sql-error) ())

(defun usage-error (format-control &rest format-args)
  (error 'usage-error
         :message (apply #'format nil format-control format-args)))

;;; ---------------------------------------------------------------------
;;; clicklisp compile

(defun cmd-compile (args)
  (let ((pretty nil)
        (inputs '())       ; (:eval . string) / (:file . path), CLI order
        (options-done nil))
    (loop while args
          do (let ((arg (pop args)))
               (cond (options-done
                      (push (cons :file arg) inputs))
                     ((string= arg "--")
                      (setf options-done t))
                     ((string= arg "--pretty")
                      (setf pretty t))
                     ((or (string= arg "-e") (string= arg "--eval"))
                      (unless args
                        (usage-error "compile: ~A needs an argument" arg))
                      (push (cons :eval (pop args)) inputs))
                     ((and (plusp (length arg)) (char= (char arg 0) #\-))
                      (usage-error "compile: unknown option ~A ~
(use -- before filenames starting with -)" arg))
                     (t (push (cons :file arg) inputs)))))
    (let ((forms (if inputs
                     (loop for (kind . value) in (nreverse inputs)
                           append (ecase kind
                                    (:eval (read-forms-from-string value))
                                    (:file (read-forms-from-file value))))
                     (read-forms-from-stream *standard-input*))))
      (when (null forms)
        (usage-error "compile: no input forms (pass -e, a file, or stdin)"))
      (let ((compiled (mapcar (lambda (form)
                                (compile-query form :pretty pretty))
                              forms)))
        (if (rest compiled)
            (format t "~{~A;~%~}" compiled)
            (format t "~A~%" (first compiled)))))
    0))

;;; ---------------------------------------------------------------------
;;; clicklisp rules json: machine-readable rule dumps

(defun json-string-literal (string)
  "Render STRING as a double-quoted JSON string literal. The output is
pure ASCII (control characters and everything past ~ escape to \\uXXXX,
astral code points as UTF-16 surrogate pairs), which makes it immune to
stream external-format differences."
  (with-output-to-string (out)
    (flet ((escape (code)
             (format out "\\u~(~4,'0x~)" code)))
      (write-char #\" out)
      (loop for char across string
            for code = (char-code char)
            do (cond ((char= char #\") (write-string "\\\"" out))
                     ((char= char #\\) (write-string "\\\\" out))
                     ((char= char #\Newline) (write-string "\\n" out))
                     ((char= char #\Tab) (write-string "\\t" out))
                     ((char= char #\Return) (write-string "\\r" out))
                     ((< code 32) (escape code))
                     ((> code #xFFFF)
                      (let ((offset (- code #x10000)))
                        (escape (+ #xD800 (ash offset -10)))
                        (escape (+ #xDC00 (logand offset #x3FF)))))
                     ((> code 126) (escape code))
                     (t (write-char char out))))
      (write-char #\" out))))

(defun rule-params (rule)
  "The {name:Type} query parameters in RULE's query, as a list of
\(NAME . TYPE) rendered strings, deduplicated by name in first-appearance
order. Parameters spliced in through (raw \"...\") strings are not seen."
  (let ((params '()))
    (labels ((param-form-p (form)
               (and (head-name-p form "PARAM")
                    (consp (rest form))
                    (consp (cddr form))
                    (null (cdddr form))))
             (record (name type)
               ;; render exactly as the compiler's param special form does
               (let ((rendered (etypecase name
                                 (string name)
                                 (symbol (substitute #\_ #\- (symbol-sql-name name))))))
                 (unless (assoc rendered params :test #'string=)
                   (push (cons rendered (type-sql type)) params))))
             (walk (form)
               (cond ((param-form-p form)
                      (record (second form) (third form)))
                     ((consp form)
                      (walk (car form))
                      (walk (cdr form)))
                     ;; vector literals compile element-wise, so params
                     ;; can hide inside them (strings hold no forms)
                     ((and (vectorp form) (not (stringp form)))
                      (map nil #'walk form)))))
      (walk (rule-query rule)))
    (nreverse params)))

(defun rule-definition-form (rule)
  "Rebuild the DEFRULE form (DEFQUERY when severity-free) that would
define RULE, as data."
  (let ((severity (rule-severity rule))
        (options '()))
    (when (rule-tags rule)
      (setf options (list* :tags (rule-tags rule) options)))
    (when severity
      (setf options (list* :severity severity options)))
    (when (rule-description rule)
      (setf options (list* :description (rule-description rule) options)))
    (list (if severity 'defrule 'defquery)
          (intern (string-upcase (rule-name rule)) '#:clicklisp.forms)
          options
          (rule-query rule))))

(defun rule-form-text (rule)
  "RULE's definition form, pretty-printed the way rule files write it."
  (let ((*package* (find-package '#:clicklisp.forms))
        (*print-pretty* t)
        (*print-case* :downcase)
        (*print-right-margin* 78)
        (*print-level* nil)
        (*print-length* nil)
        (*print-readably* nil))
    (write-to-string (rule-definition-form rule))))

(defun print-rule-json (rule stream)
  (let ((severity (rule-severity rule)))
    (format stream "    {~%")
    (format stream "      \"name\": ~A,~%"
            (json-string-literal (rule-name rule)))
    (format stream "      \"description\": ~A,~%"
            (if (rule-description rule)
                (json-string-literal (rule-description rule))
                "null"))
    (format stream "      \"severity\": ~A,~%"
            (if severity
                (json-string-literal (string-downcase (symbol-name severity)))
                "null"))
    (format stream "      \"tags\": [~{~A~^, ~}],~%"
            (mapcar (lambda (tag)
                      (json-string-literal (string-downcase (symbol-name tag))))
                    (rule-tags rule)))
    (format stream "      \"params\": [~{~A~^, ~}],~%"
            (mapcar (lambda (param)
                      (format nil "{\"name\": ~A, \"type\": ~A}"
                              (json-string-literal (car param))
                              (json-string-literal (cdr param))))
                    (rule-params rule)))
    (format stream "      \"sql\": ~A,~%"
            (json-string-literal (rule-sql rule)))
    (format stream "      \"sql_pretty\": ~A,~%"
            (json-string-literal (rule-sql rule :pretty t)))
    (format stream "      \"form\": ~A~%"
            (json-string-literal (rule-form-text rule)))
    (format stream "    }")))

(defun print-rules-json (rules &optional (stream *standard-output*))
  "Emit RULES as one JSON object carrying both compact and pretty SQL."
  (format stream "{~%")
  (format stream "  \"clicklisp\": ~A,~%" (json-string-literal *version*))
  (cond ((null rules)
         (format stream "  \"rules\": []~%"))
        (t
         (format stream "  \"rules\": [~%")
         (loop for (rule . more) on rules
               do (print-rule-json rule stream)
                  (format stream "~:[~;,~]~%" more))
         (format stream "  ]~%")))
  (format stream "}~%"))

;;; ---------------------------------------------------------------------
;;; clicklisp rules

(defun cmd-rules (args)
  (let ((loads '())
        (positionals '())
        (all nil)
        (pretty nil))
    (loop while args
          do (let ((arg (pop args)))
               (cond ((string= arg "--load")
                      (unless args (usage-error "rules: --load needs a file"))
                      (push (pop args) loads))
                     ((string= arg "--all") (setf all t))
                     ((string= arg "--pretty") (setf pretty t))
                     ((and (plusp (length arg)) (char= (char arg 0) #\-))
                      (usage-error "rules: unknown option ~A" arg))
                     (t (push arg positionals)))))
    (dolist (file (nreverse loads))
      (load-user-file file))
    (setf positionals (nreverse positionals))
    ;; the subcommand is the first positional wherever it appears, so
    ;; `rules --load f.lisp sql --all` works like `rules sql --load f.lisp --all`
    (let ((subcommand (if (and positionals
                               (member (first positionals) '("list" "sql" "json")
                                       :test #'string=))
                          (pop positionals)
                          "list"))
          (names positionals))
      (cond
        ((string= subcommand "list")
         (when (or names all)
           (usage-error "rules list takes no rule names (did you mean rules sql?)"))
         (let ((rules (list-rules)))
           (if (null rules)
               (format t "no rules loaded (use --load FILE)~%")
               (dolist (rule rules)
                 (format t "~24A ~10A ~@[~A~]~%"
                         (rule-name rule)
                         (let ((severity (rule-severity rule)))
                           (if severity (string-downcase (symbol-name severity)) ""))
                         (rule-description rule))))))
        ((string= subcommand "sql")
         (let ((rules (cond (all (list-rules))
                            (names (mapcar (lambda (name)
                                             (or (find-rule name)
                                                 (usage-error "rules: unknown rule ~A" name)))
                                           names))
                            (t (usage-error "rules sql: pass rule names or --all")))))
           (when (null rules)
             (usage-error "rules sql: no rules loaded (use --load FILE)"))
           (dolist (rule rules)
             (format t "-- ~A~@[ [~A]~]~@[ ~A~]~%~A;~%~%"
                     (rule-name rule)
                     (let ((severity (rule-severity rule)))
                       (and severity (string-downcase (symbol-name severity))))
                     (rule-description rule)
                     (rule-sql rule :pretty pretty)))))
        ((string= subcommand "json")
         ;; --pretty is accepted but a no-op here: the JSON always carries
         ;; both compact and pretty SQL.
         (let ((rules (cond (all (list-rules))
                            (names (mapcar (lambda (name)
                                             (or (find-rule name)
                                                 (usage-error "rules: unknown rule ~A" name)))
                                           names))
                            (t (usage-error "rules json: pass rule names or --all")))))
           (when (null rules)
             (usage-error "rules json: no rules loaded (use --load FILE)"))
           (print-rules-json rules)))))
    0))

;;; ---------------------------------------------------------------------
;;; clicklisp udf

(defun cmd-udf (args)
  (let ((name nil)
        (loads '())
        (chunked nil)
        (watch nil)
        (list nil))
    (loop while args
          do (let ((arg (pop args)))
               (cond ((string= arg "--fn")
                      (unless args (usage-error "udf: --fn needs a name"))
                      (setf name (pop args)))
                     ((string= arg "--load")
                      (unless args (usage-error "udf: --load needs a file"))
                      (push (pop args) loads))
                     ((string= arg "--chunked") (setf chunked t))
                     ((string= arg "--watch")
                      (unless args (usage-error "udf: --watch needs a file"))
                      (setf watch (pop args)))
                     ((string= arg "--list") (setf list t))
                     (t (usage-error "udf: unknown argument ~A" arg)))))
    (dolist (file (nreverse loads))
      (load-user-file file))
    (cond
      (list
       (dolist (udf (list-udfs))
         (format t "~24A ~@[~A~]~%" (udf-name udf) (udf-documentation udf))))
      (t
       (unless name
         (usage-error "udf: --fn NAME is required (or --list)"))
       ;; ClickHouse String values are arbitrary bytes, not necessarily
       ;; valid UTF-8; latin-1 round-trips every byte unchanged. Non-file
       ;; streams (tests) keep whatever format they have.
       (ignore-errors
        (setf (stream-external-format *standard-input*) '(:latin-1 :lf)))
       (ignore-errors
        (setf (stream-external-format *standard-output*) '(:latin-1 :lf)))
       (run-udf name :chunked chunked :watch-file watch)))
    0))

;;; ---------------------------------------------------------------------
;;; clicklisp repl

(defun cmd-repl (args)
  (let ((loads '()))
    (loop while args
          do (let ((arg (pop args)))
               (cond ((string= arg "--load")
                      (unless args (usage-error "repl: --load needs a file"))
                      (push (pop args) loads))
                     (t (usage-error "repl: unknown argument ~A" arg)))))
    (dolist (file (nreverse loads))
      (load-user-file file))
    (format t "clicklisp ~A repl (bytecode compiler; (quit) to exit)~%" *version*)
    (let ((*package* (find-package '#:clicklisp.forms))
          (*read-default-float-format* 'double-float)
          (eof '#:eof))
      (loop
        (format t "~&clicklisp> ")
        (finish-output)
        (multiple-value-bind (form read-ok)
            ;; a syntax error must not kill the session
            (handler-case (values (read *standard-input* nil eof) t)
              (error (e)
                (format t "~&read error: ~A~%" e)
                (clear-input *standard-input*)
                (values nil nil)))
          (when read-ok
            (when (eq form eof) (return))
            (when (or (head-name-p form "QUIT")
                      (and form (symbolp form)
                           (string-equal (symbol-name form) "QUIT")))
              (return))
            (handler-case
                (let ((values (multiple-value-list (eval form))))
                  (format t "~{~S~^ ;~%~}~%" values))
              (error (e)
                (format t "error: ~A~%" e)))))))
    0))

;;; ---------------------------------------------------------------------
;;; Entry point

(defun print-usage (&optional (stream *standard-output*))
  (format stream "clicklisp ~A - s-expressions in, ClickHouse out~%~
~%~
usage: clicklisp COMMAND [options]~%~
~%~
commands:~%~
  compile [--pretty] [-e SEXPR] [FILE ...]   compile query forms to SQL~%~
                                             (reads stdin when no input given)~%~
  rules [list] [--load FILE]                 list loaded rules and queries~%~
  rules sql [--load FILE] [--pretty] [--all | NAME ...]~%~
                                             emit SQL for rules and queries~%~
  rules json [--load FILE] [--all | NAME ...]~%~
                                             machine-readable JSON (with both~%~
                                             compact and pretty SQL)~%~
  udf --fn NAME [--load FILE] [--chunked] [--watch FILE]~%~
                                             serve a UDF over stdin/stdout~%~
                                             (TabSeparated, for ClickHouse~%~
                                             executable UDFs)~%~
  udf --list [--load FILE]                   list available UDFs~%~
  repl [--load FILE]                         interactive Lisp REPL~%~
  version                                    print version~%~
  help                                       this text~%"
          *version*))

(defun main (&optional (argv (command-line-arguments)))
  "CLI entry point; returns the process exit code."
  (handler-case
      (let ((command (first argv))
            (args (rest argv)))
        (cond
          ((or (null command)
               (member command '("help" "--help" "-h") :test #'string=))
           (print-usage)
           0)
          ((member command '("version" "--version") :test #'string=)
           (format t "clicklisp ~A~%" *version*)
           0)
          ((string= command "compile") (cmd-compile args))
          ((string= command "rules") (cmd-rules args))
          ((string= command "udf") (cmd-udf args))
          ((string= command "repl") (cmd-repl args))
          (t
           (format *error-output* "clicklisp: unknown command ~S~%" command)
           (print-usage *error-output*)
           2)))
    (usage-error (e)
      (format *error-output* "~A~%" e)
      2)
    (sql-error (e)
      (format *error-output* "~A~%" e)
      1)
    ;; serious-condition also covers storage-condition, e.g. ECL's
    ;; stack-overflow on pathologically nested input
    (serious-condition (e)
      (format *error-output* "clicklisp: ~A~%" e)
      1)))
