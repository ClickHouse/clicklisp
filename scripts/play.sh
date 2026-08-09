#!/bin/sh
# SQL on stdin -> the public ClickHouse playground. Compose with the
# compiler for s-expressions in, results out:
#
#   echo '(select ((count)) :from uk.uk-price-paid)' \
#     | bin/clicklisp compile | scripts/play.sh
#   bin/clicklisp rules sql --load examples/analytics/uk-price-paid.lisp price-trend \
#     | scripts/play.sh town=LONDON
#
# Extra NAME=VALUE args become server-side query parameters, bound to
# (param name :type) forms in the query. Values are spliced into the URL
# verbatim, so keep them simple (no '&', spaces, or other URL-special
# characters). One statement per invocation: the HTTP interface is
# single-statement (`rules sql` with a single rule name is fine, --all
# is not).
#
# Environment:
#   CLICKLISP_PLAY    endpoint (default: the sql.clickhouse.com backend)
#   CLICKLISP_FORMAT  output format (default: PrettyCompactMonoBlock)
set -eu

URL="${CLICKLISP_PLAY:-https://sql-clickhouse.clickhouse.com/?user=demo}"
case "$URL" in
    *\?*) URL="$URL&" ;;
    *)    URL="$URL?" ;;
esac
URL="${URL}default_format=${CLICKLISP_FORMAT:-PrettyCompactMonoBlock}"
for kv in "$@"; do
    URL="$URL&param_${kv%%=*}=${kv#*=}"
done

# --fail-with-body: exit non-zero on a rejected query while still
# printing the server's error text (needs curl >= 7.76, 2021)
curl -sS --fail-with-body "$URL" --data-binary @-
