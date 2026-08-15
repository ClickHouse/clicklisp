#!/bin/sh
# Compile the example analytics rule packs to JSON for the site's demo
# pages. Consumed by `make site-data`; the output directory is
# gitignored, and the pages workflow regenerates it on every deploy so
# the site cannot drift from the compiler.
#
# Environment:
#   BIN  path to the clicklisp binary (default: bin/clicklisp)
set -eu

cd "$(dirname "$0")/.."

BIN="${BIN:-bin/clicklisp}"
if [ ! -x "$BIN" ]; then
    echo "ERROR: $BIN not found or not executable; build it first (make all)" >&2
    exit 1
fi

mkdir -p site/src/generated

"$BIN" rules json --all --load examples/analytics/github-events.lisp > site/src/generated/github-threats.json
"$BIN" rules json --all --load examples/analytics/uk-price-paid.lisp > site/src/generated/uk-price-paid.json
"$BIN" rules json --all --load examples/analytics/hackernews.lisp > site/src/generated/hackernews.json
"$BIN" rules json --all --load examples/analytics/repo-health.lisp --load examples/analytics/repo-health-playground.lisp > site/src/generated/repo-health.json
