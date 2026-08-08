;;;; Build the clicklisp binary with ECL's AOT compiler (Lisp -> C -> native).
;;;;
;;;; This drives c:build-program directly instead of asdf:make-build: the
;;;; ASDF ECL backend routes :program builds through an intermediate .fas,
;;;; which requires :dlopen and fails on a --disable-shared (static) ECL.
;;;; The direct path works on both shared and static ECL builds.
;;;;
;;;; Extra toolchain flags come from the environment:
;;;;   CLICKLISP_CFLAGS   appended to every C compiler invocation
;;;;                      (e.g. sanitizers: -fsanitize=address,undefined)
;;;;   CLICKLISP_LDFLAGS  linker options, early in the link line
;;;;                      (e.g. -static on a musl/static ECL)

#-ecl (error "this build script targets ECL")

(require :cmp)

(defparameter *root*
  (make-pathname :name nil :type nil
                 :directory (butlast (pathname-directory *load-truename*))
                 :defaults *load-truename*))

;;; Source files in load order, read from the :serial component list in
;;; clicklisp.asd so a file added there cannot be silently missing here.
(defparameter *sources*
  (with-open-file (s (merge-pathnames "clicklisp.asd" *root*))
    (loop for form = (read s nil nil)
          while form
          when (and (consp form)
                    (symbolp (first form))
                    (string-equal (symbol-name (first form)) "DEFSYSTEM")
                    (equal (second form) "clicklisp"))
            return (or (loop for (key value) on (cddr form) by #'cddr
                             when (eq key :components)
                               return (loop for component in value
                                            when (and (consp component)
                                                      (eq (first component) :file))
                                              collect (concatenate
                                                       'string (second component) ".lisp")))
                       (error "no :components in clicklisp.asd"))
          finally (error "defsystem \"clicklisp\" not found in clicklisp.asd"))))

;;; The user flag variables must be strings (ECL tokenizes them itself).
;;; c:*user-linker-flags* replaced the deprecated c:*user-ld-flags* in 21.2.1.
(flet ((append-flags (variable-name flags)
         (let ((symbol (find-symbol variable-name '#:c)))
           (when (and symbol (boundp symbol))
             (let ((current (symbol-value symbol)))
               (setf (symbol-value symbol)
                     (if (and (stringp current) (plusp (length current)))
                         (concatenate 'string current " " flags)
                         flags)))
             t))))
  (let ((cflags (ext:getenv "CLICKLISP_CFLAGS"))
        (ldflags (ext:getenv "CLICKLISP_LDFLAGS")))
    (when (and cflags (plusp (length cflags)))
      (append-flags "*USER-CC-FLAGS*" cflags)
      (format t "~&;;; CLICKLISP_CFLAGS: ~A~%" cflags))
    (when (and ldflags (plusp (length ldflags)))
      (unless (append-flags "*USER-LINKER-FLAGS*" ldflags)
        (append-flags "*USER-LD-FLAGS*" ldflags))
      (format t "~&;;; CLICKLISP_LDFLAGS: ~A~%" ldflags))))

(let* ((objdir (merge-pathnames "build/obj/" *root*))
       (bindir (merge-pathnames "bin/" *root*))
       (objects '()))
  (ensure-directories-exist objdir)
  (ensure-directories-exist bindir)
  (dolist (source *sources*)
    (let* ((src (merge-pathnames source *root*))
           (obj (compile-file-pathname
                 (merge-pathnames (pathname-name src) objdir)
                 :type :object)))
      (format t "~&;;; compiling ~A~%" source)
      (multiple-value-bind (output warnings-p failure-p)
          (compile-file src :output-file obj :system-p t)
        (declare (ignore warnings-p))
        (when (or failure-p (null output))
          (format *error-output* "~&;;; compilation of ~A failed~%" source)
          (ext:quit 1)))
      ;; Load the source too (bytecode; a static ECL cannot dlopen the
      ;; object) so later files see this file's packages and macros.
      (load src)
      (push obj objects)))
  ;; The entry-point symbol is interned at run time: naming it as
  ;; clicklisp:main in source would fail at READ time, before the loop
  ;; above has created the package.
  (c:build-program (merge-pathnames "clicklisp" bindir)
                   :lisp-files (nreverse objects)
                   :epilogue-code (list 'ext:quit
                                        (list (intern "MAIN" "CLICKLISP")))))

(format t "~&;;; built bin/clicklisp~%")
(ext:quit 0)
