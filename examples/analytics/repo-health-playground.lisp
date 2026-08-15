;;;; The repo-health queries aimed at the public playground's pre-imported
;;;; mirror of the ClickHouse repo (git.clickhouse_* tables). The macro and
;;;; the annotated queries live in repo-health.lisp; load this file AFTER
;;;; it -- def-repo-health deliberately re-registers the same four names,
;;;; and the rule registry keeps the last definition (documented overwrite
;;;; semantics), so the playground tables win:
;;;;
;;;;   clicklisp rules sql --all --load examples/analytics/repo-health.lisp \
;;;;     --load examples/analytics/repo-health-playground.lisp
;;;;   clicklisp rules sql --load examples/analytics/repo-health.lisp \
;;;;     --load examples/analytics/repo-health-playground.lisp comment-ratio \
;;;;     | scripts/play.sh

(def-repo-health :commits git.clickhouse-commits
                 :file-changes git.clickhouse-file-changes
                 :line-changes git.clickhouse-line-changes)
