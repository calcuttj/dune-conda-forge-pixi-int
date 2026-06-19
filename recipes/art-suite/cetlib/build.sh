#!/bin/bash
# cetlib: core utility library for the art suite (plugin/library management,
# filesystem/search-path helpers, MD5/SHA1/CRC, SQLite helpers). Links boost,
# SQLite3, OpenSSL and cetlib_except. Same cetmodules build pattern as the rest.
set -euo pipefail

mkdir -p build
cd build

# CMAKE_PREFIX_PATH=$PREFIX so find_package() resolves cetmodules + cetlib_except
# (local art-suite channel) and Boost/SQLite3/OpenSSL (conda-forge) from the host
# env. BUILD_TESTING=OFF -> skip the test/ subdir (the only Catch2 user).
cmake \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF \
  -DWANT_UPS:BOOL=OFF \
  "$SRC_DIR"

make -j"${CPU_COUNT:-1}" install
