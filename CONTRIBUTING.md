# Contributing to clicklisp

Thanks for your interest in contributing. clicklisp is a small, focused project — an s-expression → ClickHouse SQL compiler and executable-UDF runner in zero-dependency Common Lisp — and this guide is correspondingly short.

## Building and testing

You need [ECL](https://ecl.common-lisp.dev/) (`brew install ecl` / `apt install ecl`) and a C compiler. There are no other dependencies — no Quicklisp, no third-party Lisp libraries.

```sh
make            # build bin/clicklisp (override the compiler: make ECL=/path/to/ecl)
make test       # run the test suite
make smoke      # end-to-end checks against the built binary
```

Before opening a pull request, make sure all three pass.

## Iterating interactively

The whole test suite runs in seconds, so the simplest loop is just `make test` after each change. The harness (`tests/harness.lisp`) is homegrown (`deftest` / `is` / `is=` / `signals-sql-error`) and has no single-test filter — `run-tests` runs everything in definition order.

To poke at a single form, use `bin/clicklisp repl` or a raw `ecl --norc`, then load the system:

```lisp
(require :asdf)
(asdf:load-asd #p"/path/to/clicklisp/clicklisp.asd")
(asdf:load-system "clicklisp/test")   ; or just "clicklisp"
```

## Ground rules for changes

- **Stay portable to ECL 21.2.1.** CI's test job deliberately uses the old apt ECL on Ubuntu 24.04, even though local development may use a much newer release. Don't use features that only exist in recent ECL.
- **Keep the docs in sync.** README.md is the primary documentation: changes to the CLI, the query language, rules, or UDFs must be reflected there. If user-facing behavior or docs change, update the site (`site/`) too. The code samples in `site/src/samples.ts` are hand-lifted verbatim from README.md and must stay identical to it.
- **Add tests.** Compiler, rules, and UDF changes need tests in `tests/` (extend `compiler-tests.lisp` or `udf-tests.lisp`, or add a new file).
- **Adding a source file:** declare it in `clicklisp.asd`'s `:components` (files load serially in the declared order). The build script parses that list, so nothing else needs to change.

## Commits and pull requests

- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/), matching the existing history (e.g. `fix(compiler): ...`, `docs(readme): ...`, `chore(deps): ...`).
- Open pull requests against `main`. CI (tests, sanitizer, static build) must pass before merge.

## Bugs, features, and security

- Bug reports and feature requests go through [GitHub issues](https://github.com/ClickHouse/clicklisp/issues).
- **Security issues must not be reported publicly.** Follow the process in [SECURITY.md](SECURITY.md) instead of opening an issue.

## License and conduct

clicklisp is licensed under [Apache-2.0](LICENSE). By contributing, you agree that your contributions are licensed under the same terms (inbound = outbound).

All participants are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
