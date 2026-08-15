<img width=64 src="logo.png">

# clicklisp

The CL in ClickHouse.

Common Lisp was hiding in the first two letters the whole time.

S-expressions in, ClickHouse out. One small static binary, built with
[ECL](https://ecl.common-lisp.dev/) (Lisp → C → native), no runtime
dependencies.

Two halves that compose:

- **A query compiler.** `(select ...)` forms become ClickHouse SQL. Queries
  are data: composable, diffable, testable. Detection rules live in a
  library of forms (`defrule`) instead of SQL string blobs.
- **Executable UDFs.** The same binary speaks ClickHouse's executable UDF
  protocol (TabSeparated over stdin/stdout). Drop it into
  `user_scripts_path`, add one XML file, and call Lisp from `SELECT` — with
  hot code reload while queries stream through the process.

```
$ echo '(select ((as (count) c))
          :from events
          :where (and (= status 500)
                      (> ts (- (now) (interval 1 :hour))))
          :group-by (user)
          :order-by ((c :desc))
          :limit 10)' | clicklisp compile
SELECT count() AS c FROM events WHERE ((status = 500) AND (ts > (now() - INTERVAL 1 HOUR))) GROUP BY user ORDER BY c DESC LIMIT 10
```

## Building

Requires ECL (`brew install ecl` / `apt install ecl`) and a C compiler.

```sh
make          # bin/clicklisp for the host platform
make test     # run the test suite (no dependencies beyond ECL)
make smoke    # end-to-end checks against the built binary
```

For the deployable single-file binary, build statically against musl in an
Alpine container (first run also builds a static ECL toolchain, ~3 min,
cached under `.cache/`):

```sh
docker run --rm \
  -v "$PWD:/src" -v "$PWD/.cache/ecl-static:/cache" -w /src \
  alpine:3.22 sh scripts/build-static.sh
```

The result is `dist/clicklisp-linux-$(uname -m)`: statically linked, a few
MB after stripping, runs on any Linux of that architecture. Release
binaries for x86_64 and aarch64 are published by the
[release workflow](.github/workflows/release.yml).

## Trying it against the public playground

[sql.clickhouse.com](https://sql.clickhouse.com) hosts ClickHouse's
[example datasets](https://clickhouse.com/docs/getting-started/example-datasets)
behind a read-only HTTP endpoint — [scripts/play.sh](scripts/play.sh)
sends it SQL from stdin, so compiled queries run against real data with
no server at all:

```sh
$ echo '(select (town (as (round (avg price)) avg-price))
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
   └───────────┴───────────┘
```

`NAME=VALUE` arguments bind server-side `(param name :type)` query
parameters; `CLICKLISP_FORMAT` and `CLICKLISP_PLAY` override the output
format and the endpoint. One statement per invocation (the ClickHouse
HTTP interface is single-statement).

The same queries run as [live demos](https://cl.clickhouse.com/#demos)
in the browser: the site's deploy workflow builds the binary, compiles
the example libraries with `rules json`, and each demo page sends the
compiled SQL to the playground with typed `param_` bindings — no server
of ours in the path.

## The query language

Operators and clause names are matched by symbol *name*, so forms can be
written in any package and built as plain data.

| Form | SQL |
|---|---|
| `event-time`, `t1.id`, `t1.*` | `event_time`, `t1.id`, `t1.*` (dashes → underscores) |
| `"text"`, `1.5`, `:null`, `t`, `nil` | `'text'`, `1.5`, `NULL`, `true`, `NULL` |
| `#(1 2 3)`, `(array 1 2)`, `(tuple 1 2)` | `[1, 2, 3]`, `[1, 2]`, `(1, 2)` |
| `(and (= a 1) (> b 2))` | `((a = 1) AND (b > 2))` |
| `(< 1 x 10)` | `((1 < x) AND (x < 10))` — comparisons chain like Lisp |
| `(in user (list "a" "b"))`, `(in id (select ...))` | `(user IN ('a', 'b'))`, subquery `IN` |
| `(like name "%admin%")`, `(between x 1 10)`, `(is-null x)` | `LIKE`, `BETWEEN`, `IS NULL` |
| `(to-start-of-hour ts)` | `toStartOfHour(ts)` — kebab-case → camelCase |
| `(json-extract-string raw "user")` | `JSONExtractString(raw, 'user')` — irregular names via registry |
| `(lambda (x) (+ x 1))` | `x -> (x + 1)` — Lisp lambdas are ClickHouse lambdas |
| `(array-map (lambda (x) (* x 2)) xs)` | `arrayMap(x -> (x * 2), xs)` |
| `(case ((> a 1) "big") (:else "small"))` | `CASE WHEN ... END` |
| `(cast x :uint64)`, `(cast x (:nullable :uint64))` | `CAST(x AS UInt64)`, `CAST(x AS Nullable(UInt64))` |
| `(param user-id :uint64)` | `{user_id:UInt64}` — server-side query parameters |
| `(as expr alias)`, `(aref tags 1)`, `(interval 10 :minutes)` | `expr AS alias`, `tags[1]`, `INTERVAL 10 MINUTE` |
| `(raw "now() - 1")`, `(fn "toIPv4" ip)` | verbatim escape hatches |

`select` takes a column list (or `*`, or `(:distinct ...)`) followed by
keyword clauses, emitted in proper ClickHouse order regardless of how you
write them:

```lisp
(select (user (as (count) hits))
  :with ((threshold 20))                       ; CTEs: scalar or (name (select ...))
  :from (as (select ...) sub)                  ; tables, subqueries, (final tbl)
  :join (:left t2 :on (= t1.id t2.id))         ; or a list of join specs, :using (...)
  :array-join (tags)                           ; and :left-array-join
  :prewhere (= shard 3)
  :where (> hits threshold)
  :group-by (user)  :with-totals t             ; also :with-rollup / :with-cube
  :having (> hits 10)
  :order-by ((hits :desc :nulls-last))
  :limit-by (3 user)
  :limit 100  :offset 10
  :settings ((max_threads 4))
  :format "JSONEachRow")
```

`(union-all q1 q2)` and `(union-distinct ...)` combine queries. Strings are
escaped, identifiers are validated or backtick-quoted, every infix
expression is parenthesized — precedence bugs are structurally impossible,
and injection requires an explicit `(raw ...)`.

Unknown functions map kebab→camelCase automatically; teach the compiler
irregular ClickHouse spellings with
`(define-sql-function my-fn "MyClickHouseName")` and types with
`(define-sql-type geo-point "Point")`.

The `sql` macro compiles at macroexpansion time — a rule library costs
nothing at runtime:

```lisp
(sql (select (1)))   ; => the literal string "SELECT 1"
```

## Detection rules

```lisp
;; rules.lisp
(defrule ssh-bruteforce
    (:description "Hosts with > 20 failed SSH logins in 10 minutes"
     :severity :high
     :tags (:t1110 :ssh))
  (select ((as source-ip ip) (as (count) attempts))
    :from auth-events
    :where (and (= event-type "ssh_login_failed")
                (> event-time (- (now) (interval 10 :minutes))))
    :group-by (source-ip)
    :having (> attempts 20)))
```

Rules are validated (compiled) at load time and rendered on demand:

```sh
clicklisp rules --load rules.lisp                 # list
clicklisp rules sql --load rules.lisp --all       # emit SQL for all
clicklisp rules sql --load rules.lisp ssh-bruteforce
clicklisp rules json --load rules.lisp --all      # machine-readable JSON
```

`rules json` dumps each rule as JSON — `name`, `description`, `severity`,
`tags`, the extracted `{name:Type}` `params`, compact `sql`, multiline
`sql_pretty`, and the reconstructed `form` — for anything downstream that
wants rules as data; it is what feeds the
[live demos](https://cl.clickhouse.com/#demos) at build time.

See [examples/rules.lisp](examples/rules.lisp).

Exit codes: `0` success, `1` bad input (a query that does not compile),
`2` bad invocation.

## Query libraries, not query files

`defquery` is `defrule` minus the detection metadata: named queries for
any domain, served by the same `rules` commands.
[examples/analytics/](examples/analytics/) has four libraries built on
the playground's example datasets:

- [uk-price-paid.lisp](examples/analytics/uk-price-paid.lisp) — UK
  property sales: parameterized queries, parametric aggregates via
  `(fn "quantile(0.9)" price)`, a `(raw ...)` window function, and a
  macro that stamps out one price-league query per property type.
- [repo-health.lisp](examples/analytics/repo-health.lisp) — engineering
  analytics (code churn, bus factor, comment-to-code ratio) over
  `clickhouse git-import` tables; the whole library is one macro
  parameterized by table names, so it runs against *your* repo locally,
  and [repo-health-playground.lisp](examples/analytics/repo-health-playground.lisp)
  re-invokes it against the playground's pre-imported ClickHouse mirror
  (load both files; the second registration wins).
- [hackernews.lisp](examples/analytics/hackernews.lisp) — text search,
  array lambdas, CTE composition, and a query that calls back into a
  clicklisp executable UDF.
- [github-events.lisp](examples/analytics/github-events.lisp) — a
  `defrule` threat pack over 11 billion rows of public GitHub events
  (`github.events`): branch-reset storms, mass ref deletion, tag
  retargeting, star storms, bulk collaborator adds, commit-hour
  anomalies, each tagged with MITRE ATT&CK technique IDs. Two rules
  default to historical windows because the dataset's loader stopped
  populating `push_size` and tag `CreateEvent`s around October 2025 —
  see the file header.

Rule files are full Common Lisp, and queries are data — so a macro can
generate a family of queries with no copy-paste and no templating
language:

```lisp
(defmacro def-price-league (ptype)
  `(defquery ,(intern (format nil "TOP-~A-DISTRICTS" ptype))
       (:description ,(format nil "Priciest districts for ~(~A~) sales" ptype))
     (select (district (as (round (avg price)) avg-price))
       :from uk.uk-price-paid
       :where (= type ,(string-downcase (string ptype)))
       :group-by (district)
       :order-by ((avg-price :desc))
       :limit 10)))

(def-price-league flat)       ; => top-flat-districts
(def-price-league detached)   ; => top-detached-districts, ...
```

Parameterized queries bind server-side through `play.sh` arguments:

```sh
$ bin/clicklisp rules sql --load examples/analytics/uk-price-paid.lisp price-trend \
    | scripts/play.sh town=LONDON
    ┌─year─┬─avg_price─┬─trend──────────┐
 1. │ 1995 │    109154 │ █▍             │
 2. │ 1996 │    118686 │ █▌             │
...
29. │ 2023 │   1026396 │ █████████████▋ │
    └──────┴───────────┴────────────────┘
```

`clicklisp repl --load examples/analytics/uk-price-paid.lisp` gives you
the same registry interactively: evaluate another `(def-price-league ...)`
form, then `(princ (rule-sql (find-rule "top-flat-districts")))`.

Two authoring notes: a one-element `:order-by ((year))` is read as the
*call* `year()` — write `:order-by (year)` or `((year :desc))` — and
executable-UDF calls must be written snake_case (`(clicklisp_shout x)`),
since kebab-case would camelCase to `clicklispShout(x)`.

## Executable UDFs

Define a function, and the binary serves it over ClickHouse's executable
UDF protocol:

```lisp
(defudf entropy (s)
  "Shannon entropy in bits/char - flags DGA-style domains."
  ...)
```

```sh
printf 'clickhouse\nq7x9z2j4k8w1.evil.example\n' | clicklisp udf --fn entropy
3.121928094887362
4.213660689688184
```

UDFs load from plain Lisp files too —
[examples/udfs/text.lisp](examples/udfs/text.lisp) defines `shout`, a
clickbait score (fraction of letters that are uppercase):

```sh
$ printf 'HELLO World\n' | clicklisp udf --fn shout --load examples/udfs/text.lisp
0.6
```

Deploy on a self-managed server: copy `bin/clicklisp` into
`user_scripts_path` (default `/var/lib/clickhouse/user_scripts/`), and a
config like [examples/clicklisp_function.xml](examples/clicklisp_function.xml)
next to the server config (the filename must match the
`user_defined_executable_functions_config` glob, default `*_function.*ml`):

```sql
SELECT domain, clicklisp_entropy(domain) AS h
FROM dns_events WHERE h > 3.8
```

Protocol notes (all handled by `clicklisp udf`):

- `TabSeparated`: one row per line, fields tab-separated, `\t \n \\`
  escaped, `\N` for NULL. Output rows must match input rows one-to-one.
- `type=executable` spawns a process per block and closes stdin;
  `type=executable_pool` keeps long-lived processes that must loop forever
  and flush per chunk. `clicklisp udf` flushes per row, or per chunk with
  `--chunked` when the config sets `<send_chunk_header>1</send_chunk_header>`
  (ClickHouse then precedes each block with its row count).
- A failing row logs to stderr and yields `\N` instead of killing the pool.
- The UDF streams are byte-transparent (latin-1), so non-UTF-8 bytes in
  String values round-trip instead of crashing the process.

### Trying it against a local ClickHouse

Run a ClickHouse server in Docker with the static Linux binary (from
`scripts/build-static.sh` or a release) mounted into `user_scripts_path`
— on Apple Silicon the aarch64 build runs natively in the container:

```sh
# clicklisp-linux-aarch64 on Apple Silicon, clicklisp-linux-x86_64 on Intel
docker run -d --name clicklisp-ch \
  -v "$PWD/dist/clicklisp-linux-aarch64:/var/lib/clickhouse/user_scripts/clicklisp" \
  -v "$PWD/examples/udfs/text.lisp:/var/lib/clickhouse/user_scripts/text.lisp" \
  -v "$PWD/examples/clicklisp_function.xml:/etc/clickhouse-server/clicklisp_function.xml" \
  clickhouse/clickhouse-server:latest

docker exec clicklisp-ch clickhouse-client \
  -q "SELECT clicklisp_entropy('q7x9z2j4k8w1'), clicklisp_shout('READ THIS now')"
```

Load the [Hacker News dataset](https://clickhouse.com/docs/getting-started/example-datasets/hacker-news)
into the container and the `shouting-titles` query in
[examples/analytics/hackernews.lisp](examples/analytics/hackernews.lisp)
ranks real stories with it — SQL compiled from Lisp calling back into
Lisp per row.

Detection rules compile on the host and pipe straight into the server,
calling back into the Lisp UDF:

```sh
bin/clicklisp rules sql --load examples/rules.lisp dga-domains \
  | grep -v '^--' \
  | docker exec -i clicklisp-ch clickhouse-client --format PrettyCompact
```

UDF stderr (failed rows, hot-reload notices) lands in the server log:
`docker logs clicklisp-ch`. Tear down with `docker rm -f clicklisp-ch`.

### Hot patching

`--watch` re-loads a Lisp file whenever it changes, *while the pool process
keeps serving queries* — using ECL's in-image bytecode compiler, so it
works inside the UDF sandbox where no C toolchain exists. The
`clicklisp_shout` entry in
[examples/clicklisp_function.xml](examples/clicklisp_function.xml) is
wired this way:

```xml
<function>
    <type>executable_pool</type>
    <name>clicklisp_shout</name>
    <command>clicklisp udf --fn shout --load user_scripts/text.lisp --watch user_scripts/text.lisp --chunked</command>
    <format>TabSeparated</format>
    <argument><type>String</type></argument>
    <return_type>Float64</return_type>
    <send_chunk_header>1</send_chunk_header>
</function>
```

Edit `text.lisp` in `user_scripts_path`, save, and the next block is
served by the new definition. `clicklisp repl` gives you the same
live-coding loop locally.

ClickHouse Cloud note: executable UDFs on Cloud are in public beta but
Python-shaped (ZIP with `main.py` uploaded via the console) — the native
binary path here targets self-managed ClickHouse; the experimental
driver-based UDF mechanism in ClickHouse master is the future hook for
compiling Lisp at `CREATE FUNCTION` time.

## CI

- **test** — the suite plus a full binary build and smoke test, with the
  distro ECL, on `ubuntu-24.04` and `ubuntu-24.04-arm`.
- **sanitize** — builds ECL 26.5.5 from source with ASan+UBSan on both
  architectures (build-time flags propagate into ECL's runtime Lisp→C
  compiler, so all generated code is instrumented), then runs the suite
  and the binary under the sanitizers. The toolchain is cached.
- **static** — the Alpine/musl static builds for x86_64 and aarch64.
- **release** — pushing a tag `vX.Y.Z` (which must match `version.sexp`)
  builds both static binaries and publishes them with SHA256SUMS to a
  GitHub release.
- **pages** — builds the binary with the distro ECL, generates the demo
  data (`make site-data`), builds the site, and deploys it to
  [cl.clickhouse.com](https://cl.clickhouse.com) — so the demos are
  compiled by the same commit they document.

Supply-chain posture: every workflow action is pinned to a commit SHA
(dependabot keeps the pins fresh), workflows run with least-privilege
`permissions`, the ECL source tarball is SHA256-verified before it is
built, and the Alpine build image is pinned by digest.

## Layout

```
src/names.lisp            identifier/function/type naming, quoting, literals
src/compiler.lisp         the s-expression -> SQL compiler
src/rules.lisp            defrule/defquery registry
src/udf.lisp              TabSeparated UDF loop, defudf, hot reload
src/main.lisp             CLI entry point
build/build.lisp          ECL AOT build (c:build-program; works on static ECL)
scripts/build-static.sh   static musl build, run inside alpine:3.22
scripts/play.sh           pipe SQL from stdin to the public ClickHouse playground
scripts/gen-site-data.sh  compile the example libraries to JSON for the site demos
examples/                 detection rules, analytics libraries, UDFs, server config
site/                     cl.clickhouse.com — docs plus live demos of the libraries
tests/                    zero-dependency harness + suite
```
