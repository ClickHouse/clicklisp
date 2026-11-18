;;;; GitHub events threat pack (github.events on the public playground):
;;;; the defrule idea aimed at 11 billion rows of public GitHub activity.
;;;;
;;;; Row limit: the playground's demo user reads at most one billion rows
;;;; per query and stops there without an error (read_overflow_mode =
;;;; break), so a query that does not prune below that returns a partial
;;;; answer that looks complete. github.events is sorted by (event_type,
;;;; repo_name, toDate(created_at)). An event_type alone is enough for
;;;; WatchEvent (560 million rows), DeleteEvent (340 million) and
;;;; MemberEvent (37 million), but PushEvent has 6.5 billion rows and
;;;; CreateEvent 1.5 billion. The two rules that read those take an org
;;;; parameter, the part of repo_name before the slash, which prunes them
;;;; to a few hundred thousand rows for an organization the size of
;;;; ClickHouse. When you write a new rule here, try it once with
;;;; :settings ((read_overflow_mode "throw")): the playground then refuses
;;;; a query it would otherwise cut short. Avoid github.github_events
;;;; (sorted by repo_id first, so none of this prunes) and
;;;; git.github_events (a View).
;;;;
;;;;   clicklisp rules sql --load examples/analytics/github-events.lisp branch-reset-storm \
;;;;     | scripts/play.sh org=ClickHouse since=2024-04-15T00:00:00 until=2024-04-22T00:00:00
;;;;   clicklisp rules sql --load examples/analytics/github-events.lisp mass-ref-deletion \
;;;;     | scripts/play.sh hours=24 min_deletions=10
;;;;   clicklisp rules sql --load examples/analytics/github-events.lisp star-storm \
;;;;     | scripts/play.sh min_stars=5
;;;;
;;;; play.sh splices parameter values into the URL verbatim, so write
;;;; DateTime values with the ISO T separator, never a space.
;;;;
;;;; Loader caveats: the feed stopped populating push_size /
;;;; push_distinct_size and stopped recording tag CreateEvents around
;;;; October 2025, so branch-reset-storm and tag-retarget only fire on
;;;; windows before that; known-good values are in their comments. The
;;;; feed has also been thin and uneven since mid-2026 (about 110,000
;;;; stars in the first half of November 2026, against 3.6 to 4.2 million
;;;; a month in mid-2025), which is why the thresholds of star-storm and
;;;; mass-ref-deletion are parameters.

;; push_distinct_size = 0 with push_size > 0 means no commit in the push
;; was new to the repo: the ref was pointed at already-pushed commits (a
;; reset/rollback, a cross-branch promotion, a mirror sync). The public
;; feed carries no forced flag, and a rebase force-push arrives as
;; all-new SHAs, so true force-push detection is not possible from this
;; dataset -- this flags actors doing bulk ref resets instead, minus the
;; merge-queue-style [bot] accounts that do it legitimately all day.
;; PushEvent is the largest event type by far, so the rule looks at one
;; organization (or user) at a time: org is the part of repo_name before
;; the slash. push_size stopped being populated ~Oct 2025 -- query a
;; window before that, e.g. org=ClickHouse since=2024-04-15T00:00:00
;; until=2024-04-22T00:00:00.
(defrule branch-reset-storm
    (:description "Actors resetting a repo's refs to already-pushed commits 10+ times in a window, in one organization's repos"
     :severity :medium
     :tags (:t1565.001 :github :push))
  (select (actor-login repo-name (as (count) resets))
    :from github.events
    :where (and (= event-type "PushEvent")
                (starts-with repo-name (concat (param org :string) "/"))
                (>= created-at (param since :date-time))
                (< created-at (param until :date-time))
                (> push-size 0)
                (= push-distinct-size 0)
                (not (like actor-login "%[bot]%")))
    :group-by (actor-login repo-name)
    :having (>= resets 10)
    :order-by ((resets :desc))
    :limit 50))

;; Branch/tag mass deletion: destructive cleanup, or an account wiping
;; the evidence. Window and threshold are bound server-side, e.g.
;; hours=24 min_deletions=10 (50 was the bar on the full feed).
(defrule mass-ref-deletion
    (:description "Actors with {min_deletions:UInt32}+ ref deletions in one repo within {hours:UInt32} hours"
     :severity :high
     :tags (:t1485 :github))
  (select (actor-login repo-name (as (count) deletions) (as (uniq-exact ref) refs))
    :from github.events
    :where (and (= event-type "DeleteEvent")
                (>= created-at (- (now) (interval (param hours :uint32) :hours))))
    :group-by (actor-login repo-name)
    :having (>= deletions (param min-deletions :uint32))
    :order-by ((deletions :desc))
    :limit 50))

;; A tag deleted and recreated in the same window now points somewhere
;; else -- the classic release-retarget supply-chain move. Scoped to
;; one organization like branch-reset-storm: Create and Delete events
;; together are more than the playground reads. Tag CreateEvents stopped
;; ~Oct 2025 -- query a window before that, e.g. org=ClickHouse
;; since=2024-08-05T00:00:00 until=2024-08-12T00:00:00.
(defrule tag-retarget
    (:description "Tags deleted and recreated in the same window in one organization's repos (release retarget)"
     :severity :critical
     :tags (:t1195.002 :github :supply-chain))
  (select (repo-name ref
           (as (count-if (= event-type "DeleteEvent")) deleted)
           (as (count-if (= event-type "CreateEvent")) recreated))
    :from github.events
    :where (and (in event-type (list "DeleteEvent" "CreateEvent"))
                (starts-with repo-name (concat (param org :string) "/"))
                (= ref-type "tag")
                (>= created-at (param since :date-time))
                (< created-at (param until :date-time)))
    :group-by (repo-name ref)
    :having (and (>= deleted 1) (>= recreated 1))
    :order-by (((+ deleted recreated) :desc))
    :limit 50))

;; Repos gaining many stars in a single hour of the last day: launch-day
;; traffic, or a bought star campaign. The threshold is bound server-side,
;; e.g. min_stars=5 on today's thin feed (50 was the bar on the full one).
(defrule star-storm
    (:description "Repos gaining {min_stars:UInt32}+ stars in one hour over the last 24 hours"
     :severity :medium
     :tags (:t1585.001 :github :stars))
  (select (repo-name (as (to-start-of-hour created-at) hour)
           (as (count) stars) (as (uniq-exact actor-login) actors))
    :from github.events
    :where (and (= event-type "WatchEvent")
                (>= created-at (- (now) (interval 24 :hours))))
    :group-by (repo-name hour)
    :having (>= stars (param min-stars :uint32))
    :order-by ((stars :desc))
    :limit 50))

;; Five or more collaborators added to one repo in a month: onboarding a
;; team, or a compromised owner handing out write access.
(defrule bulk-collaborator-add
    (:description "Repos adding 5+ collaborators in the last 30 days"
     :severity :medium
     :tags (:t1098 :github :access))
  (select (repo-name (as (count) adds)
           (as (group-uniq-array member-login) members))
    :from github.events
    :where (and (= event-type "MemberEvent")
                (= action "added")
                (>= created-at (- (now) (interval 30 :days))))
    :group-by (repo-name)
    :having (>= adds 5)
    :order-by ((adds :desc))
    :limit 50))

;; Hour-of-day profile for one repo's pushes: hours busy since {since}
;; (recent >= 10) yet quiet across all prior history (recent > 2x
;; baseline) suggest activity from someone in the wrong timezone. An
;; empty result is the healthy outcome. E.g. repo=ClickHouse/ClickHouse
;; since=2026-07-15T00:00:00.
(defrule commit-hour-anomaly
    (:description "Push hours for a repo that are busy recently but rare historically"
     :severity :low
     :tags (:t1078 :github :anomaly))
  (select ((as (to-hour created-at) hour)
           (as (count-if (>= created-at (param since :date-time))) recent)
           (as (- (count) recent) baseline)
           (as (bar recent 0 100 20) trend))
    :from github.events
    :where (and (= event-type "PushEvent")
                (= repo-name (param repo :string)))
    :group-by (hour)
    :having (and (>= recent 10) (> recent (* 2 baseline)))
    :order-by (hour)))
