ECL ?= ecl
BIN := bin/clicklisp
SOURCES := clicklisp.asd version.sexp $(wildcard src/*.lisp)

.PHONY: all test smoke site-data clean

all: $(BIN)

$(BIN): $(SOURCES) build/build.lisp
	$(ECL) --norc --load build/build.lisp

test:
	$(ECL) --norc --load tests/run-tests.lisp

smoke: $(BIN)
	$(BIN) version
	echo '(select ((as (count) c)) :from events :where (> ts (- (now) 3600)))' | $(BIN) compile
	$(BIN) compile -e '(select (user) :from logins :where (= ok 0) :limit 10)'
	printf 'clickhouse\nq7x9z2j4k8w1.evil.example\n' | $(BIN) udf --fn entropy
	printf 'uryyb\n' | $(BIN) udf --fn rot13
	printf 'HELLO World\n' | $(BIN) udf --fn shout --load examples/udfs/text.lisp
	$(BIN) rules sql --all --load examples/rules.lisp
	$(BIN) rules sql --all --load examples/analytics/uk-price-paid.lisp
	$(BIN) rules sql --all --load examples/analytics/repo-health.lisp
	$(BIN) rules sql --all --load examples/analytics/hackernews.lisp
	$(BIN) rules sql --all --load examples/analytics/github-events.lisp
	$(BIN) rules sql --all --load examples/analytics/repo-health.lisp --load examples/analytics/repo-health-playground.lisp
	$(BIN) rules json --all --load examples/rules.lisp | python3 -m json.tool > /dev/null
	@echo smoke OK

site-data: $(BIN)
	scripts/gen-site-data.sh

clean:
	rm -rf bin
