;;;; Text-scoring UDFs. Serve locally:
;;;;
;;;;   printf 'HELLO World\n' | clicklisp udf --fn shout --load examples/udfs/text.lisp
;;;;
;;;; or from ClickHouse via the clicklisp_shout entry in
;;;; examples/clicklisp_function.xml, which also --watches this file:
;;;; edit it in user_scripts_path and the next block is served by the
;;;; new definition.

(defudf shout (s)
  "Fraction of letters that are uppercase - a clickbait/shouting score."
  (if (or (null s) (zerop (length s)))
      0.0d0
      (let ((letters 0)
            (upper 0))
        (loop for char across s
              when (alpha-char-p char)
                do (incf letters)
                   (when (upper-case-p char) (incf upper)))
        (if (zerop letters)
            0.0d0
            (/ upper (float letters 1.0d0))))))
