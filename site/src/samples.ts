// Code samples shown on the page. All are real, runnable examples lifted
// from the README so the site never drifts from what the binary does.

export const heroLisp = `$ echo '(select ((as (count) c))
          :from events
          :where (and (= status 500)
                      (> ts (- (now) (interval 1 :hour))))
          :group-by (user)
          :order-by ((c :desc))
          :limit 10)' | clicklisp compile`;

export const heroSql = `SELECT count() AS c FROM events WHERE ((status = 500) AND (ts > (now() - INTERVAL 1 HOUR))) GROUP BY user ORDER BY c DESC LIMIT 10`;

export const ruleExample = `;; rules.lisp
(defrule ssh-bruteforce
    (:description "Hosts with > 20 failed SSH logins in 10 minutes"
     :severity :high
     :tags (:t1110 :ssh))
  (select ((as source-ip ip) (as (count) attempts))
    :from auth-events
    :where (and (= event-type "ssh_login_failed")
                (> event-time (- (now) (interval 10 :minutes))))
    :group-by (source-ip)
    :having (> attempts 20)))`;

export const rulesCli = `clicklisp rules --load rules.lisp                 # list
clicklisp rules sql --load rules.lisp --all       # emit SQL for all
clicklisp rules sql --load rules.lisp ssh-bruteforce
clicklisp rules json --load rules.lisp --all      # machine-readable JSON`;

export const macroExample = `(defmacro def-price-league (ptype)
  \`(defquery ,(intern (format nil "TOP-~A-DISTRICTS" ptype))
       (:description ,(format nil "Priciest districts for ~(~A~) sales" ptype))
     (select (district (as (round (avg price)) avg-price))
       :from uk.uk-price-paid
       :where (= type ,(string-downcase (string ptype)))
       :group-by (district)
       :order-by ((avg-price :desc))
       :limit 10)))

(def-price-league flat)       ; => top-flat-districts
(def-price-league detached)   ; => top-detached-districts, ...`;

export const udfDefinition = `(defudf entropy (s)
  "Shannon entropy in bits/char - flags DGA-style domains."
  ...)`;

export const udfShell = `$ printf 'clickhouse\\nq7x9z2j4k8w1.evil.example\\n' \\
    | clicklisp udf --fn entropy
3.121928094887362
4.213660689688184`;

export const udfSql = `SELECT domain, clicklisp_entropy(domain) AS h
FROM dns_events WHERE h > 3.8`;

export const udfXml = `<function>
    <type>executable_pool</type>
    <name>clicklisp_shout</name>
    <command>clicklisp udf --fn shout --load user_scripts/text.lisp --watch user_scripts/text.lisp --chunked</command>
    <format>TabSeparated</format>
    <argument><type>String</type></argument>
    <return_type>Float64</return_type>
    <send_chunk_header>1</send_chunk_header>
</function>`;

export const playgroundShell = `$ echo '(select (town (as (round (avg price)) avg-price))
          :from uk.uk-price-paid
          :where (>= date (to-date "2025-01-01"))
          :group-by (town)
          :having (> (count) 1000)
          :order-by ((avg-price :desc))
          :limit 3)' | bin/clicklisp compile | scripts/play.sh

   ┌─town──────┬─avg_price─┐
1. │ LONDON    │    859963 │
2. │ RICHMOND  │    797900 │
3. │ SEVENOAKS │    768441 │
   └───────────┴───────────┘`;

export const installShell = `# build from source (any platform with ECL + a C compiler)
brew install ecl        # or: apt install ecl
make                    # -> bin/clicklisp
make test               # zero-dependency test suite

# or grab a static Linux binary from the latest release
curl -fLO https://github.com/ClickHouse/clicklisp/releases/latest/download/clicklisp-linux-x86_64
curl -fLO https://github.com/ClickHouse/clicklisp/releases/latest/download/clicklisp-linux-aarch64`;

// Rows for the Lisp -> SQL cheatsheet table.
export const languagePairs: Array<{ lisp: string; sql: string; note?: string }> = [
  { lisp: "event-time, t1.id", sql: "event_time, t1.id", note: "dashes become underscores" },
  { lisp: "(< 1 x 10)", sql: "((1 < x) AND (x < 10))", note: "comparisons chain like Lisp" },
  { lisp: "(to-start-of-hour ts)", sql: "toStartOfHour(ts)", note: "kebab-case becomes camelCase" },
  { lisp: "(lambda (x) (+ x 1))", sql: "x -> (x + 1)", note: "Lisp lambdas are ClickHouse lambdas" },
  { lisp: "#(1 2 3)", sql: "[1, 2, 3]", note: "vectors are arrays" },
  { lisp: "(param user-id :uint64)", sql: "{user_id:UInt64}", note: "server-side query parameters" },
  { lisp: "(cast x (:nullable :uint64))", sql: "CAST(x AS Nullable(UInt64))" },
  { lisp: '(case ((> a 1) "big") (:else "small"))', sql: "CASE WHEN (a > 1) THEN 'big' ELSE 'small' END" },
];

export const fullSelect = `(select (user (as (count) hits))
  :with ((threshold 20))                  ; CTEs: scalar or (name (select ...))
  :from (as (select ...) sub)             ; tables, subqueries, (final tbl)
  :join (:left t2 :on (= t1.id t2.id))    ; or a list of join specs, :using
  :array-join (tags)                      ; and :left-array-join
  :prewhere (= shard 3)
  :where (> hits threshold)
  :group-by (user)  :with-totals t        ; also :with-rollup / :with-cube
  :having (> hits 10)
  :order-by ((hits :desc :nulls-last))
  :limit-by (3 user)
  :limit 100  :offset 10
  :settings ((max_threads 4))
  :format "JSONEachRow")`;
