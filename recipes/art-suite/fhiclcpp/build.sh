#!/bin/bash
# fhiclcpp: the FHiCL configuration language library + CLI tools. Same cetmodules
# build pattern. find_package(cetlib) transitively pulls cetlib's exported deps
# (boost/sqlite/openssl/cetlib_except), all present in the host env.
set -euo pipefail

mkdir -p build
cd build

cmake \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF \
  -DWANT_UPS:BOOL=OFF \
  "$SRC_DIR"

make -j"${CPU_COUNT:-1}" install
