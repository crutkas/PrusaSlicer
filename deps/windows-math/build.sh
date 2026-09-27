#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

root=$(cygpath -u "$1")
toolchain=$(cygpath -u "$2")
target=$3
export PATH="$toolchain/bin:/usr/bin"
export CC="$target-clang"
export CXX="$target-clang++"
export AR=llvm-ar
export NM=llvm-nm
export RANLIB=llvm-ranlib
export STRIP=llvm-strip
export DLLTOOL=llvm-dlltool
export CFLAGS="-O2 -std=gnu11 -D__USE_MINGW_ANSI_STDIO=0"
export CXXFLAGS="-O2 -D__USE_MINGW_ANSI_STDIO=0"
if [[ "$target" == x86_64-* ]]; then
    # Match MSVC's long double ABI, including MPFR's public get/set_ld API.
    CFLAGS="$CFLAGS -mlong-double-64"
    CXXFLAGS="$CXXFLAGS -mlong-double-64"
fi
export LC_ALL=C
export TZ=UTC
prefix="$root/install"
mkdir -p "$root/build-gmp" "$root/build-mpfr"

cd "$root/build-gmp"
../src/gmp-6.2.1/configure \
    --build="$target" --host="$target" --prefix="$prefix" \
    --disable-assembly --disable-static --enable-shared --disable-cxx \
    2>&1 | tee "$root/logs/gmp-configure.log"
make -j2 2>&1 | tee "$root/logs/gmp-build.log"
make -j2 check 2>&1 | tee "$root/logs/gmp-check.log"
make install 2>&1 | tee "$root/logs/gmp-install.log"

export PATH="$prefix/bin:$PATH"
cd "$root/build-mpfr"
../src/mpfr-4.2.1/configure \
    --build="$target" --host="$target" --prefix="$prefix" \
    --with-gmp="$prefix" --disable-static --enable-shared \
    --enable-thread-safe \
    2>&1 | tee "$root/logs/mpfr-configure.log"
make -j2 2>&1 | tee "$root/logs/mpfr-build.log"
make -j2 check 2>&1 | tee "$root/logs/mpfr-check.log"
make install 2>&1 | tee "$root/logs/mpfr-install.log"
