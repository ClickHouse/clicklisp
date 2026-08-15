;;;; Engineering analytics over git history -- the defrule idea pointed at
;;;; your own codebase instead of a SIEM.
;;;;
;;;; `clickhouse git-import` (bundled with any clickhouse binary) turns a
;;;; checkout into three TSVs; load them into the commits / file_changes /
;;;; line_changes tables from its printed DDL, then:
;;;;
;;;;   clicklisp rules sql --all --load examples/analytics/repo-health.lisp
;;;;
;;;; The library is parameterized over table names, so the same queries run
;;;; against the playground's pre-imported mirrors of the ClickHouse and
;;;; Grafana repos (databases git.clickhouse_* / git.grafana_*).

(defmacro def-repo-health (&key (commits 'commits)
                                (file-changes 'file-changes)
                                (line-changes 'line-changes))
  `(progn
     (defquery comment-ratio
         (:description "Comment-to-code ratio per author (added lines)"
          :tags (:repo))
       (select (author
                (as (count-if (= line-type "Comment")) comment-lines)
                (as (count-if (= line-type "Code")) code-lines)
                (as (round (/ comment-lines (+ code-lines 1)) 3) ratio))
         :from ,line-changes
         :where (= sign 1)
         :group-by (author)
         :having (> code-lines 1000)
         :order-by ((ratio :desc))
         :limit 20))

     (defquery bus-factor-1
         (:description "Files with more than 10 changes and exactly one author"
          :tags (:repo :risk))
       (select (path (as (uniq-exact author) authors) (as (count) changes))
         :from ,file-changes
         :group-by (path)
         :having (and (= authors 1) (> changes 10))
         :order-by ((changes :desc))
         :limit 20))

     (defquery file-rewrites
         (:description "Commits that rewrote a file (threshold via {min_lines:UInt32})"
          :tags (:repo))
       (select ((as (substring commit-hash 1 8) commit) path lines-added lines-deleted)
         :from ,file-changes
         :where (and (> lines-added (param min-lines :uint32))
                     (> lines-deleted (param min-lines :uint32))
                     (= change-type "Modify"))
         :order-by (((+ lines-added lines-deleted) :desc))
         :limit 30))

     (defquery activity-heatmap
         (:description "Commits by day-of-week and hour"
          :tags (:repo))
       (select ((as (to-day-of-week time) dow) (as (to-hour time) hour)
                (as (count) commits) (as (bar (count) 0 500 20) intensity))
         :from ,commits
         :group-by (dow hour)
         :order-by (dow hour)))))

;; Local git-import tables by default. To aim at the playground's
;; ClickHouse-repo mirror instead, load repo-health-playground.lisp after
;; this file -- it re-registers the same four names against the
;; git.clickhouse_* tables.
(def-repo-health)
