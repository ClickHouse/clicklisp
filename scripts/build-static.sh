#!/bin/sh
# Build a fully static clicklisp binary. Runs INSIDE an Alpine container:
#
#   docker run --rm \
#     -v "$PWD:/src" -v "$PWD/.cache/ecl-static:/cache" -w /src \
#     alpine:3.22 sh scripts/build-static.sh
#
# First run builds a static (--disable-shared) ECL toolchain into /cache
# (~3 minutes); later runs reuse it. The result lands in
# dist/clicklisp-linux-$(uname -m): one self-contained file, no runtime
# dependencies, ready for ClickHouse's user_scripts_path.
set -eu

ECL_VERSION="${ECL_VERSION:-26.5.5}"
ECL_TARBALL="https://ecl.common-lisp.dev/static/files/release/ecl-${ECL_VERSION}.tgz"
ECL_PREFIX="/cache/ecl-${ECL_VERSION}-static"
ARCH="$(uname -m)"

apk add --no-cache build-base gmp-dev gmp-static curl file

if [ ! -x "$ECL_PREFIX/bin/ecl" ]; then
    echo "=== building static ECL $ECL_VERSION for musl/$ARCH"
    rm -rf /tmp/ecl-src
    mkdir -p /tmp/ecl-src
    curl -fsSL "$ECL_TARBALL" | tar xz -C /tmp/ecl-src --strip-components=1
    cd /tmp/ecl-src
    # In-tree configure (ECL's wrapper does not support external build dirs).
    # The bundled GMP is ancient (4.2.1); Alpine's gmp-static provides a
    # current libgmp.a. bdwgc and libatomic_ops come from the ECL tree.
    ./configure --prefix="$ECL_PREFIX" \
                --disable-shared \
                --enable-threads=yes \
                --enable-boehm=included \
                --enable-libatomic=included \
                --enable-gmp=system \
                --with-dffi=no \
                --enable-manual=no
    make -j"$(nproc)"
    make install
    rm -rf /tmp/ecl-src
fi

echo "=== building clicklisp"
cd /src
rm -rf bin build/obj
CLICKLISP_LDFLAGS="-static" "$ECL_PREFIX/bin/ecl" --norc --load build/build.lisp
strip bin/clicklisp

echo "=== verifying the binary is static"
file bin/clicklisp
if ldd bin/clicklisp 2>/dev/null; then
    echo "ERROR: bin/clicklisp is dynamically linked" >&2
    exit 1
fi

echo "=== smoke tests"
bin/clicklisp version
echo '(select ((as (count) c)) :from events :where (> ts (- (now) 3600)))' \
    | bin/clicklisp compile
printf 'clickhouse\n' | bin/clicklisp udf --fn entropy
printf 'uryyb\n' | bin/clicklisp udf --fn rot13
bin/clicklisp rules sql --all --load examples/rules.lisp > /dev/null

mkdir -p dist
cp bin/clicklisp "dist/clicklisp-linux-${ARCH}"
echo "=== OK: dist/clicklisp-linux-${ARCH} ($(du -h bin/clicklisp | cut -f1))"
