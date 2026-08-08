ECL ?= ecl
BIN := bin/clicklisp
SOURCES := clicklisp.asd version.sexp $(wildcard src/*.lisp)

.PHONY: all test smoke clean

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
	$(BIN) rules sql --all --load examples/rules.lisp
	@echo smoke OK

clean:
	rm -rf bin
