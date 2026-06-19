#!/bin/bash
# cetmodules is a pure CMake/Perl/Bash build-helper product -- project() declares
# LANGUAGES NONE, so there is nothing to compile. `make install` just stages the
# CMake Modules, the generated cetmodulesConfig.cmake and the helper scripts.
#
# Non-UPS mode is the default; WANT_UPS:BOOL=OFF is set explicitly so no UPS
# table/setup machinery is emitted into $PREFIX.
set -euo pipefail

mkdir -p build
cd build

cmake \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DWANT_UPS:BOOL=OFF \
  "$SRC_DIR"

make -j"${CPU_COUNT:-1}" install
