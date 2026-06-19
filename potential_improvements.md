# Potential improvements to the art-suite internal build (CMake / cetmodules)

Findings collected while packaging the FNAL art suite as conda packages. These
are upstream-facing notes: places where the products' own CMake / cetmodules
setup forces awkward workarounds in a non-UPS, distro-style build. None are
blockers — each has a recipe-side workaround — but fixing them upstream would
make the suite cleaner to package (conda, spack, or plain CMake installs).

Format: one entry per finding — what, where, why it bites, suggested fix.

---

## 1. `find_package(Catch2 REQUIRED)` is unconditional (cetlib_except)

- **Where:** `cetlib_except/CMakeLists.txt` (the source subdir), top of file —
  runs `find_package(Catch2 REQUIRED)` *outside* any `if(BUILD_TESTING)` guard.
- **Why it bites:** Catch2 is a *test* dependency (UPS `product_deps` marks
  `catch ... only_for_build`), yet configure hard-fails without it even when
  `-DBUILD_TESTING=OFF`. So every consumer/packager must install Catch2 just to
  configure a library that, in a no-tests build, doesn't link it. The lone
  non-test use is the `cetlib_except::Catch2Matchers` INTERFACE target, which is
  itself only useful to downstream *tests*.
- **Suggested fix:** guard the `find_package(Catch2)` and the `Catch2Matchers`
  target behind `if(BUILD_TESTING)` (or register Catch2 as an optional
  component / `find_package(Catch2 QUIET)` and only define `Catch2Matchers` when
  found). Then a tests-off build needs no Catch2 at all.
- **Recipe workaround:** add `catch2 3.3.*` to `host:` regardless of
  `BUILD_TESTING`.

---

## 2. `cet_set_compiler_flags(... WERROR ...)` has no external off-switch

- **Where:** products call `cet_set_compiler_flags(DIAGS VIGILANT WERROR ...)`
  in their top-level `CMakeLists.txt` (e.g. cetlib_except). cetmodules
  `Modules/SetCompilerFlags.cmake` implements it as a bare
  `add_compile_options(-Werror)` when the `WERROR` keyword is present.
- **Why it bites:** `-Werror` + a vigilant warning set (`-Wall -Wextra
  -pedantic ...`) is baked in at the directory level via `add_compile_options`,
  which lands on the compile line *after* `CMAKE_CXX_FLAGS`/`$CXXFLAGS`. So a
  packager **cannot** demote it from outside — appending `-Wno-error` to
  `CXXFLAGS` loses the left-to-right ordering battle. Newer compilers than the
  product targeted (e.g. conda's GCC 13/14 vs an older reference) routinely
  introduce new warnings; with no escape hatch the only options are to patch the
  source or pin an old compiler. (WCT hit the same class of problem and solved
  it by faking a "development" version string to drop release `-Werror`.)
- **Suggested fix:** honor a standard cache/option override, e.g. respect
  `CET_WARNINGS_ARE_ERRORS` (default ON) or a `-DCETMODULES_NO_WERROR=ON` so the
  `add_compile_options(-Werror)` can be suppressed without editing sources.
- **Recipe workaround (if it bites):** carry a per-product patch removing the
  `WERROR` keyword (mirrors the WCT `-Werror` patch strategy), since a
  CXXFLAGS-based demotion does not work.

---

## 3. Inconsistent / missing LICENSE files across products

- **Where:** `hep-concurrency` v1_09_02 ships **no** `LICENSE` file in its
  release tarball, whereas `cetlib_except` v1_09_01 does (identical FNAL
  BSD-3-Clause text). Likely varies product-to-product across the suite.
- **Why it bites:** packaging tooling (conda `license_file:`, spack, Debian, …)
  expects each release to carry its license text. A missing file forces the
  packager to either omit license provenance or vendor the text from elsewhere.
- **Suggested fix:** ship the same top-level `LICENSE` in every product's repo
  /release tarball (a one-line addition per repo).
- **Recipe workaround:** set the SPDX `license:` but omit `license_file:` for
  products that don't ship one.

## 4. Undeclared dependency: OpenSSL (cetlib)

- **Where:** `cetlib/cetlib/CMakeLists.txt` line ~73 does
  `find_package(OpenSSL REQUIRED EXPORT)` + links `OpenSSL::Crypto` (non-Apple),
  but `ups/product_deps` lists no `openssl` product.
- **Why it bites:** the dependency is invisible to anything that reads
  `product_deps` (UPS, and any tooling that mirrors it to derive a recipe's deps,
  as this packaging effort does). A from-`product_deps` recipe would fail to
  configure until OpenSSL is added by hand. UPS likely got OpenSSL implicitly
  from the system/compiler bundle, masking the omission.
- **Suggested fix:** add `openssl` (or the suite's chosen SSL product) to
  cetlib's `product_deps` so the declared dep graph matches the CMake reality.
- **Recipe workaround:** add `openssl` to `host:`.

## 5. Missing `#include <cassert>` (fhiclcpp)

- **Where:** `fhiclcpp/DatabaseSupport.cc` calls `assert()` (line ~23) but never
  includes `<cassert>`. (Watch for the same missing-standard-header class of bug
  in other products — `<cstdint>`, `<cassert>`, `<algorithm>`, `<memory>` are the
  usual suspects.)
- **Why it bites:** older libstdc++ pulled `<cassert>` in transitively via other
  standard headers; newer libstdc++ (conda-forge GCC) does not, so the build
  fails with `'assert' was not declared in this scope`. This is a latent
  correctness bug, not a warning — `-Werror` is irrelevant here.
- **Suggested fix:** add the explicit `#include <cassert>` upstream (and audit
  the suite for other implicit standard-header reliance).
- **Recipe workaround:** carry a patch adding the include
  (`patches/0001-DatabaseSupport-include-cassert.patch`).

<!-- Add new findings above this line as the climb up the dep graph continues. -->
