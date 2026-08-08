;;;; Entry point for `make test`: load the system and run the suite.

(require :asdf)

(asdf:load-asd (merge-pathnames "../clicklisp.asd" *load-truename*))
(asdf:load-system "clicklisp/test")

(uiop:quit (if (uiop:symbol-call '#:clicklisp/test '#:run-tests) 0 1))
