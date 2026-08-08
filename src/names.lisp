;;;; Naming, quoting and literal rendering for the ClickHouse SQL backend.

(in-package #:clicklisp)

;;; ---------------------------------------------------------------------
;;; Conditions

(define-condition sql-error (error)
  ((message :initarg :message :reader sql-error-message)
   (form :initarg :form :initform nil :reader sql-error-form))
  (:report (lambda (condition stream)
             (format stream "clicklisp: ~A~@[ in form ~S~]"
                     (sql-error-message condition)
                     (sql-error-form condition)))))

(defun sql-fail (form format-control &rest format-args)
  (error 'sql-error
         :form form
         :message (apply #'format nil format-control format-args)))

;;; ---------------------------------------------------------------------
;;; String helpers

(defun split-string (string char)
  (loop with length = (length string)
        for start = 0 then (1+ position)
        for position = (position char string :start start)
        collect (subseq string start (or position length))
        while position))

(defun join-strings (strings separator)
  (with-output-to-string (out)
    (loop for (string . more) on strings
          do (write-string string out)
             (when more (write-string separator out)))))

(defun capitalize-first (string)
  (if (zerop (length string))
      string
      (concatenate 'string
                   (string (char-upcase (char string 0)))
                   (subseq string 1))))

(defun kebab->camel (name)
  "to-start-of-hour => toStartOfHour"
  (let ((parts (split-string name #\-)))
    (format nil "~A~{~A~}" (first parts) (mapcar #'capitalize-first (rest parts)))))

;;; ---------------------------------------------------------------------
;;; Symbol names
;;;
;;; The standard reader upcases symbol names, so an all-uppercase name is
;;; folded to lowercase; a name with any lowercase character was escaped
;;; (|arrayMap|) and is preserved as written.

(defun symbol-sql-name (symbol)
  (let ((name (symbol-name symbol)))
    (if (notany #'lower-case-p name)
        (string-downcase name)
        name)))

;;; ---------------------------------------------------------------------
;;; Identifiers

(defparameter +reserved-words+
  (let ((table (make-hash-table :test 'equalp)))
    (dolist (word '("select" "from" "where" "group" "order" "by" "limit"
                    "offset" "having" "join" "on" "using" "as" "and" "or"
                    "not" "in" "between" "like" "ilike" "case" "when" "then"
                    "else" "end" "union" "all" "distinct" "prewhere"
                    "settings" "format" "with" "array" "final" "sample"
                    "inner" "left" "right" "full" "cross" "asof" "semi"
                    "anti" "any" "global" "interval" "true" "false" "null"
                    "exists" "is" "desc" "asc" "window" "qualify" "table"
                    "database" "values" "default" "primary" "key" "to")
             table)
      (setf (gethash word table) t))
    table))

(defun plain-identifier-char-p (char)
  (or (char<= #\a char #\z)
      (char<= #\A char #\Z)
      (char<= #\0 char #\9)
      (char= char #\_)))

(defun plain-identifier-p (name)
  (and (plusp (length name))
       (let ((first (char name 0)))
         (or (char<= #\a first #\z)
             (char<= #\A first #\Z)
             (char= first #\_)))
       (every #'plain-identifier-char-p name)
       (not (gethash name +reserved-words+))))

(defun quote-identifier (name)
  (with-output-to-string (out)
    (write-char #\` out)
    (loop for char across name
          do (when (or (char= char #\`) (char= char #\\))
               (write-char #\\ out))
             (write-char char out))
    (write-char #\` out)))

(defun render-identifier-part (name)
  (if (plain-identifier-p name)
      name
      (quote-identifier name)))

(defun identifier-sql (id)
  "Render ID as a ClickHouse identifier. Symbols map dashes to underscores
and may be dotted (events.user, t1.*); strings are used verbatim, though
still backtick-quoted when they are not plain identifiers."
  (etypecase id
    (string
     (if (plusp (length id))
         (render-identifier-part id)
         (sql-fail id "empty identifier")))
    (symbol
     (let ((name (symbol-sql-name id)))
       (join-strings
        (mapcar (lambda (part)
                  (cond ((string= part "*") "*")
                        ((zerop (length part))
                         (sql-fail id "empty identifier component in ~A" name))
                        (t (render-identifier-part (substitute #\_ #\- part)))))
                (split-string name #\.))
        ".")))))

;;; ---------------------------------------------------------------------
;;; Function names
;;;
;;; Unknown function symbols map kebab-case to camelCase, which covers the
;;; bulk of the ClickHouse function namespace. Irregular names (JSON*,
;;; IPv4*, ...) live in a registry that DEFINE-SQL-FUNCTION extends.

(defparameter *function-names* (make-hash-table :test 'equal))

(defun register-sql-function (lisp-name clickhouse-name)
  (setf (gethash (string-downcase (string lisp-name)) *function-names*)
        clickhouse-name))

(defmacro define-sql-function (lisp-name clickhouse-name)
  "Map LISP-NAME (a symbol or string, matched case-insensitively) to the
verbatim ClickHouse function name CLICKHOUSE-NAME."
  `(register-sql-function ',lisp-name ,clickhouse-name))

(loop for (lisp clickhouse)
        in '(("json-extract" "JSONExtract")
             ("json-extract-string" "JSONExtractString")
             ("json-extract-int" "JSONExtractInt")
             ("json-extract-uint" "JSONExtractUInt")
             ("json-extract-float" "JSONExtractFloat")
             ("json-extract-bool" "JSONExtractBool")
             ("json-extract-raw" "JSONExtractRaw")
             ("json-extract-array-raw" "JSONExtractArrayRaw")
             ("json-extract-keys" "JSONExtractKeys")
             ("json-extract-keys-and-values" "JSONExtractKeysAndValues")
             ("json-has" "JSONHas")
             ("json-length" "JSONLength")
             ("json-type" "JSONType")
             ("to-json-string" "toJSONString")
             ("ipv4-num-to-string" "IPv4NumToString")
             ("ipv4-string-to-num" "IPv4StringToNum")
             ("ipv6-num-to-string" "IPv6NumToString")
             ("ipv6-string-to-num" "IPv6StringToNum")
             ("ipv4-cidr-to-range" "IPv4CIDRToRange")
             ("ipv6-cidr-to-range" "IPv6CIDRToRange")
             ("is-ipv4-string" "isIPv4String")
             ("is-ipv6-string" "isIPv6String")
             ("is-ip-address-in-range" "isIPAddressInRange")
             ("to-ipv4" "toIPv4")
             ("to-ipv6" "toIPv6")
             ("to-ipv4-or-null" "toIPv4OrNull")
             ("to-ipv6-or-null" "toIPv6OrNull")
             ("to-uuid" "toUUID")
             ("to-uuid-or-null" "toUUIDOrNull")
             ("generate-uuid-v4" "generateUUIDv4")
             ("md5" "MD5")
             ("half-md5" "halfMD5")
             ("sha1" "SHA1")
             ("sha224" "SHA224")
             ("sha256" "SHA256")
             ("sha512" "SHA512")
             ("crc32" "CRC32")
             ("crc64" "CRC64")
             ("url-hash" "URLHash")
             ("url-hierarchy" "URLHierarchy")
             ("url-path-hierarchy" "URLPathHierarchy")
             ("cut-url-parameter" "cutURLParameter")
             ("extract-url-parameter" "extractURLParameter")
             ("extract-url-parameters" "extractURLParameters")
             ("extract-url-parameter-names" "extractURLParameterNames")
             ("decode-url-component" "decodeURLComponent")
             ("encode-url-component" "encodeURLComponent")
             ("cut-www" "cutWWW")
             ("domain-without-www" "domainWithoutWWW")
             ("uniq-hll12" "uniqHLL12")
             ("to-datetime" "toDateTime")
             ("to-datetime64" "toDateTime64")
             ("to-datetime-or-null" "toDateTimeOrNull"))
      do (register-sql-function lisp clickhouse))

(defun function-name-sql (head)
  (etypecase head
    (string head)
    (symbol
     (let* ((name (symbol-sql-name head))
            (registered (gethash (string-downcase name) *function-names*)))
       (cond (registered registered)
             ;; escaped mixed-case symbols (|arrayMap|) pass through
             ((some #'upper-case-p name) name)
             ((find #\- name) (kebab->camel name))
             (t name))))))

;;; ---------------------------------------------------------------------
;;; Type names (for CAST, PARAM, ...)

(defparameter *type-names* (make-hash-table :test 'equal))

(defun register-sql-type (lisp-name clickhouse-name)
  (setf (gethash (string-downcase (string lisp-name)) *type-names*)
        clickhouse-name))

(defmacro define-sql-type (lisp-name clickhouse-name)
  "Map LISP-NAME (matched case-insensitively) to the verbatim ClickHouse
type name CLICKHOUSE-NAME."
  `(register-sql-type ',lisp-name ,clickhouse-name))

(dolist (name '("UInt8" "UInt16" "UInt32" "UInt64" "UInt128" "UInt256"
                "Int8" "Int16" "Int32" "Int64" "Int128" "Int256"
                "Float32" "Float64" "BFloat16"
                "Decimal" "Decimal32" "Decimal64" "Decimal128" "Decimal256"
                "String" "FixedString" "UUID"
                "Date" "Date32" "DateTime" "DateTime64"
                "Enum8" "Enum16" "IPv4" "IPv6" "Bool" "JSON"
                "Dynamic" "Variant" "Nothing"
                "Array" "Map" "Tuple" "Nullable" "LowCardinality"
                "AggregateFunction" "SimpleAggregateFunction"))
  (register-sql-type name name))

(loop for (alias type) in '(("fixed-string" "FixedString")
                            ("low-cardinality" "LowCardinality")
                            ("date-time" "DateTime")
                            ("date-time64" "DateTime64")
                            ("aggregate-function" "AggregateFunction")
                            ("simple-aggregate-function" "SimpleAggregateFunction"))
      do (register-sql-type alias type))

(defun type-arg-sql (arg)
  (cond ((integerp arg) (princ-to-string arg))
        ((stringp arg) (string-literal arg))
        ((or (symbolp arg) (consp arg)) (type-sql arg))
        (t (sql-fail arg "bad type argument ~S" arg))))

(defun type-sql (spec)
  "Render a type spec: a string is used verbatim, a symbol is looked up in
the type registry, and (nullable :uint64) style lists render as
parametric types like Nullable(UInt64)."
  (cond
    ((stringp spec)
     (if (plusp (length spec)) spec (sql-fail spec "empty type name")))
    ((and spec (symbolp spec))
     (or (gethash (string-downcase (symbol-sql-name spec)) *type-names*)
         (sql-fail spec "unknown type ~A; register it with define-sql-type, ~
or pass the entire type as a single string like \"Array(Point)\" ~
(a string nested inside a type spec becomes a quoted literal, as in ~
DateTime64(3, 'UTC'))" spec)))
    ((consp spec)
     (format nil "~A(~{~A~^, ~})"
             (type-sql (first spec))
             (mapcar #'type-arg-sql (rest spec))))
    (t (sql-fail spec "bad type spec ~S" spec))))

;;; ---------------------------------------------------------------------
;;; Literals

(defun string-literal (string)
  (with-output-to-string (out)
    (write-char #\' out)
    (loop for char across string
          do (cond ((char= char #\') (write-string "\\'" out))
                   ((char= char #\\) (write-string "\\\\" out))
                   ((char= char #\Newline) (write-string "\\n" out))
                   ((char= char #\Tab) (write-string "\\t" out))
                   ((char= char #\Return) (write-string "\\r" out))
                   ((char= char (code-char 0)) (write-string "\\0" out))
                   (t (write-char char out))))
    (write-char #\' out)))

(defun float-sql (x)
  (let ((*read-default-float-format*
          (cond ((typep x 'double-float) 'double-float)
                ((typep x 'single-float) 'single-float)
                ((typep x 'long-float) 'long-float)
                (t 'short-float))))
    (princ-to-string x)))

(defun number-sql (x)
  (typecase x
    (integer (princ-to-string x))
    (ratio (format nil "(~A / ~A)" (numerator x) (denominator x)))
    (float (float-sql x))
    (t (sql-fail x "cannot render number ~S" x))))
