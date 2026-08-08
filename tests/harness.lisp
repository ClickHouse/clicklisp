;;;; A tiny zero-dependency test harness, so the repo needs no Quicklisp.

(defpackage #:clicklisp/test
  (:use #:cl #:clicklisp)
  (:export #:deftest #:is #:is= #:signals-sql-error #:run-tests))

(in-package #:clicklisp/test)

(defparameter *tests* '())
(defparameter *assertions* 0)
(defparameter *failures* 0)

(defmacro deftest (name &body body)
  `(progn
     (setf *tests* (remove ',name *tests* :key #'car))
     (setf *tests* (append *tests* (list (cons ',name (lambda () ,@body)))))
     ',name))

(defun record-failure (format-control &rest format-args)
  (incf *failures*)
  (format t "~&  FAIL: ~?~%" format-control format-args))

(defun run-assertion (form thunk)
  (incf *assertions*)
  (handler-case
      (unless (funcall thunk)
        (record-failure "~S" form))
    (error (e)
      (record-failure "~S signaled: ~A" form e))))

(defmacro is (form)
  `(run-assertion ',form (lambda () ,form)))

(defun run-equality (form thunk expected)
  (incf *assertions*)
  (handler-case
      (let ((actual (funcall thunk)))
        (unless (equal expected actual)
          (record-failure "~S~%    expected: ~S~%    actual:   ~S"
                          form expected actual)))
    (error (e)
      (record-failure "~S signaled: ~A" form e))))

(defmacro is= (expected form)
  `(run-equality ',form (lambda () ,form) ,expected))

(defun run-signals (form thunk)
  (incf *assertions*)
  (handler-case
      (progn
        (funcall thunk)
        (record-failure "~S did not signal SQL-ERROR" form))
    (sql-error () nil)
    (error (e)
      (record-failure "~S signaled ~A instead of SQL-ERROR" form e))))

(defmacro signals-sql-error (form)
  `(run-signals ',form (lambda () ,form)))

(defun run-tests ()
  "Run every test; print failures; return T when all pass."
  (setf *assertions* 0
        *failures* 0)
  (dolist (entry *tests*)
    (format t "~&~A~%" (car entry))
    (handler-case (funcall (cdr entry))
      (error (e)
        (incf *failures*)
        (format t "~&  ERROR in test body: ~A~%" e))))
  (format t "~&~D assertion~:P, ~D failure~:P~%" *assertions* *failures*)
  (zerop *failures*))
