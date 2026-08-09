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
                               (member (first positionals) '("list" "sql")
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
                     (rule-sql rule :pretty pretty)))))))
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
