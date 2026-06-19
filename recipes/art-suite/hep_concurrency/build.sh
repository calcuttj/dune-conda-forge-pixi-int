#!/bin/bash
# hep_concurrency: cetmodules-based C++ library (SerialTaskQueue, WaitingTask,
# thread-safe utilities) built on TBB. Same build pattern as cetlib_except.
set -euo pipefail

mkdir -p build
cd build

# CMAKE_PREFIX_PATH=$PREFIX so find_package(cetmodules), find_package(cetlib_except)
# (local art-suite channel) and find_package(TBB) (conda-forge tbb-devel) resolve
# against the host env. BUILD_TESTING=OFF -> the test/ subdir (the only Catch2
# user) is skipped, so no catch2 is needed at configure time here.
cmake \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF \
  -DWANT_UPS:BOOL=OFF \
  "$SRC_DIR"

make -j"${CPU_COUNT:-1}" install
