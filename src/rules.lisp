;;;; Detection rules: named, tagged query forms kept as data.

(in-package #:clicklisp)

(defstruct (rule (:constructor %make-rule))
  name          ; canonical lowercase string
  description   ; string or nil
  severity      ; one of +severities+, or nil for a plain query (DEFQUERY)
  tags          ; list of keywords
  query)        ; the query form, as data

(defparameter +severities+ '(:info :low :medium :high :critical))

(defparameter *rules* (make-hash-table :test 'equal))

(defun rule-key (name)
  (string-downcase (string name)))

(defun register-rule (name options query)
  (destructuring-bind (&key description (severity :medium) tags) options
    (unless (or (null severity) (member severity +severities+))
      (sql-fail name "rule ~A: severity must be one of ~{~S~^, ~}"
                name +severities+))
    ;; Compile now so a broken rule fails at load time, not at query time.
    (compile-query query)
    (setf (gethash (rule-key name) *rules*)
          (%make-rule :name (rule-key name)
                      :description description
                      :severity severity
                      :tags tags
                      :query query))
    name))

(defmacro defrule (name (&rest options) query)
  "Define a detection rule. OPTIONS is a plist with :description,
:severity (:info :low :medium :high :critical) and :tags. QUERY is a
query form, kept as data and compiled on demand with RULE-SQL."
  `(register-rule ',name ',options ',query))

(defmacro defquery (name (&rest options) query)
  "Define a named query with no detection metadata: like DEFRULE but
severity-free, for query libraries that are not detections. OPTIONS is
a plist with :description and :tags."
  (when (member :severity options)
    (sql-fail name "defquery ~A takes no :severity (use defrule)" name))
  `(register-rule ',name (list* :severity nil ',options) ',query))

(defun find-rule (name)
  (gethash (rule-key name) *rules*))

(defun list-rules ()
  (let ((rules '()))
    (maphash (lambda (key rule)
               (declare (ignore key))
               (push rule rules))
             *rules*)
    (sort rules #'string< :key #'rule-name)))

(defun rule-sql (rule &key pretty)
  (compile-query (rule-query rule) :pretty pretty))
