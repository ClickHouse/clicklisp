;;;; Example detection rules: queries as data, compiled to ClickHouse SQL.
;;;;
;;;;   clicklisp rules sql --all --load examples/rules.lisp

(defrule ssh-bruteforce
    (:description "Hosts with more than 20 failed SSH logins in 10 minutes"
     :severity :high
     :tags (:t1110 :ssh))
  (select ((as source-ip ip) (as (count) attempts))
    :from auth-events
    :where (and (= event-type "ssh_login_failed")
                (> event-time (- (now) (interval 10 :minutes))))
    :group-by (source-ip)
    :having (> attempts 20)
    :order-by ((attempts :desc))))

(defrule dga-domains
    (:description "DNS lookups of high-entropy domains (uses the clicklisp_entropy executable UDF)"
     :severity :medium
     :tags (:t1568 :dns))
  (select ((as query-name domain) (as (count) lookups))
    :from dns-events
    :where (and (> (clicklisp_entropy query-name) 3.8)
                (> (length query-name) 20)
                (> event-time (- (now) (interval 1 :hour))))
    :group-by (query-name)
    :order-by ((lookups :desc))
    :limit 100))

(defrule impossible-travel
    (:description "Same user logging in from two countries within an hour"
     :severity :critical
     :tags (:t1078 :auth))
  (select (user (as (uniq-exact geo-country) countries))
    :from (final login-events)
    :where (> event-time (- (now) (interval 1 :hour)))
    :group-by (user)
    :having (> countries 1)))

(defrule rare-user-agents
    (:description "User agents seen fewer than 5 times today"
     :severity :low
     :tags (:http)
     )
  (select (user-agent (as (count) hits))
    :from http-events
    :where (>= event-time (to-start-of-day (now)))
    :group-by (user-agent)
    :having (< hits 5)
    :order-by ((hits :asc))
    :limit 50))
