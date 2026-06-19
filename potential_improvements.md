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
- **Recipe workaround (RESOLVED 2026-06-19):** the full audit found the LICENSE
  is **byte-identical** (`614e9b4d3111aaa34eec789e7ba173e0`) across all eight
  art-framework-suite products that ship it (cetlib_except, cetlib, fhiclcpp,
  messagefacility, canvas, canvas_root_io, art, plus the FNALssi cetmodules,
  which has its own but equivalent FNAL BSD text). Only **hep_concurrency** and
  **art_root_io** omit it. Every recipe now declares `license: BSD-3-Clause` +
  `license_file: LICENSE`; for the two that omit it we vendored the canonical
  sibling LICENSE into the recipe dir (`recipes/art-suite/{hep_concurrency,
  art_root_io}/LICENSE`). rattler-build 0.66.2 resolves `license_file` from the
  source dir if present, else the recipe dir — `license_file: LICENSE` works for
  both cases and ships `info/licenses/LICENSE`. Upstream fix still wanted: add
  the file to the hep-concurrency and art-root-io release tarballs.

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

## 6. `std::unique` return value ignored (canvas) — latent dedup bug

- **Where:** `canvas/Persistency/Provenance/RangeSet.cc:309`:
  `unique(merged.begin(), merged.end());` — the return value (new logical end)
  is discarded. To actually deduplicate, it must be the erase-unique idiom:
  `merged.erase(unique(b,e), merged.end());`. As written, "removed" duplicates
  are merely shuffled to the tail and left in the vector.
- **Why it bites:** `std::unique` is `[[nodiscard]]` in newer libstdc++
  (conda-forge GCC), so the suite's `VIGILANT + WERROR` flags turn this into a
  hard build error. On FNAL's older reference compiler it was at most a warning,
  so the shipped binary carries the latent bug silently.
- **Suggested fix:** use the erase-unique idiom (also fixes the real dedup bug).
- **Recipe workaround:** we did NOT change the logic (to reproduce the binary
  FNAL ships); instead we dropped `-Werror` for canvas
  (`patches/0001-drop-WERROR.patch`). This is the concrete instance of #2.
  First product where `-Werror` actually bit.

## 7. PREFIX-ROOT doc pollution → fatal README file-vs-directory clash with ROOT

This is a **two-sided** problem; both sides are worth raising with their
respective upstreams. The core issue: a conda/spack environment merges every
package into ONE `$PREFIX` tree, so any top-level path name is effectively
global. Docs/licenses do not belong at the prefix root at all — by convention
they go in package metadata (conda `info/licenses/`, copied via `license_file:`)
or a scoped `share/doc/<pkg>/`. Two upstreams violate this and collide.

### 7a. art-suite (cetmodules) — installs INSTALL/LICENSE/README as PREFIX-ROOT files
- **Where:** cetmodules' `cet_cmake_env()` calls `install_pkgmeta()`, which
  auto-finds a product's top-level `INSTALL`/`LICENSE`/`README` and installs them
  as plain files at `$PREFIX/`. Confirmed in **cetmodules, cetlib_except, cetlib,
  fhiclcpp, and canvas_root_io** (any product whose source carries those docs);
  canvas/hep_concurrency/messagefacility happen not to.
- **Why it bites — two distinct failures, both against ROOT's `$PREFIX/README/`
  directory (see 7b):**
  - *Link-time `ENOTDIR (os error 20)`:* a cet `README` **file** and ROOT's
    `README/` **directory** want the same path; rattler can't build the directory
    tree under a file.
  - *Post-build `EPERM (os error 13)`:* for a product whose host env already
    contains ROOT (**canvas_root_io, #7**), cetmodules installs our `README`
    **file** over ROOT's existing `README/` **directory** — cmake drops the file
    inside the dir AND chmods the **directory** to 0644 (loses `+x`), so
    rattler-build's post-build step can no longer traverse `README/` → EPERM.
    **Our build corrupts a dependency's directory.** NB: this was misdiagnosed as a
    rattler-build bug for a while; it is not — a fully pristine-cache rebuild
    reproduced it, and the cause is entirely our own install.
- **PROPER FIX (in our control) — `NO_INSTALL_PKGMETA`:** patch the product's
  top-level `CMakeLists.txt` to `cet_cmake_env(NO_INSTALL_PKGMETA)` (documented
  option in cetmodules `CetCMakeEnv.cmake`). It suppresses the `install_pkgmeta()`
  auto-install entirely — no prefix-root docs are staged, ROOT's dir is untouched.
  canvas_root_io does this via `patches/0002-no-install-pkgmeta.patch`. **This is
  the required fix for any ROOT-co-installed product** (#7 canvas_root_io; expect
  the same at #9 art_root_io).
- **Suggested fix (art-suite devs):** default `cet_cmake_env` away from prefix-root
  doc installs, or install under `share/doc/<product>/`. They don't belong at root.
- **The lower products do something different — and we deliberately did NOT
  retrofit them.** cetmodules `_1`, cetlib_except `_1`, cetlib `_2`, fhiclcpp `_2`
  instead **strip** `$PREFIX/{INSTALL,LICENSE,README}` after `make install`. That
  works *only because ROOT is not in their host env* — the path is their own plain
  file, so `rm -f` succeeds. It is the inferior approach (`NO_INSTALL_PKGMETA` is
  preferred), but those packages are green and were left as-is on purpose; don't
  "fix" them unless you're already touching them. **Do NOT use strip-after-install
  for a ROOT-dependent product:** the chmod happens *during* `make install` (too
  late to undo), and the path is ROOT's directory (you can't `rm` it; a guarded
  `[ -f ]` strip is just a silent no-op). Use `NO_INSTALL_PKGMETA`.
  See the `check-prefix-collisions` skill.

### 7b. ROOT — installs `$PREFIX/README/` as a DIRECTORY (the aberrant half)
- **Where:** conda-forge `root_base` (and ROOT upstream) ship a whole
  `$PREFIX/README/` **directory** (`README/ReleaseNotes/...`, `README/INSTALL`,
  `README/CREDITS`, ...) — i.e. ROOT claims the conventionally-a-FILE name
  `README` as a directory, at the environment root.
- **Why it bites:** `README` is universally a top-level *file* across the software
  landscape; using it as a directory name in a shared prefix is the genuinely
  unusual choice and is what turns any other package's `README` file into a hard
  conflict. Even absent the collision, dumping a doc tree at `$PREFIX/README/`
  pollutes the environment root.
- **Suggested fix (ROOT / conda-forge root-feedstock):** install these docs under
  a scoped path (`share/doc/root/...` or `share/root/README/`), not the prefix
  root, and don't use the bare name `README` for a directory.
- **Note:** we can't repackage `root_base`, so the actionable lever on our side is
  7a (`NO_INSTALL_PKGMETA` — don't stage prefix-root docs); raising 7b upstream
  removes the root cause.

## 8. checkClassVersion (PyROOT) can't initialize in a sandboxed build

- **Where:** cetmodules `build_dictionary()` / `art_dictionary()` runs
  `checkClassVersion` (a PyROOT script, `$PREFIX/libexec/checkClassVersion`) after
  generating each ROOT dictionary, to verify ClassDef checksums. cetmodules
  force-enables it whenever `root-config --features` reports `pyroot`/`python`
  (CheckClassVersion.cmake `_verify_pyroot`).
- **Why it bites:** in an isolated build sandbox (rattler-build; likely any
  hermetic build), `import ROOT` fails to bring up cling/cppyy
  (`cppyy.gbl has no attribute 'gSystem'`, "no interpreter information for class
  TFunction"). rootcling and the generated `.cxx`/`.pcm` compile fine -- only the
  PyROOT *post-validation* dies -- but it still fails the build. There is no
  documented knob on `art_dictionary()` to skip it short of `NO_CHECK_CLASS_VERSION`
  per call.
- **Suggested fix:** make the class-version check non-fatal (or auto-skip) when
  PyROOT can't initialize, rather than hard-failing the build; or expose a
  project-level toggle.
- **Recipe workaround:** pass `-D_CheckClassVersion_ENABLED:BOOL=FALSE` to cmake
  (pre-defines the internal cache var so `_verify_pyroot` is skipped and
  check_class_version() early-returns). Applies to every ROOT-dictionary product
  (canvas_root_io, art_root_io).

## 9. art: widespread implicit standard-header reliance (`<algorithm>`/`<cassert>`/`<cstdint>`/`<limits>`)

- **Where (art v3_14_04):** the #5 "missing standard header" class bites hard here
  given art's size. Non-test TUs that call `std::any_of`/`find_if`/etc. without
  `<algorithm>` (11 files, incl. `Framework/Principal/Selector.h:216`), `assert()`
  without `<cassert>` (22 files, incl. `Framework/IO/Sources/detail/FileServiceProxy.cc`),
  fixed-width ints without `<cstdint>` (3) and `std::numeric_limits` without
  `<limits>` (2).
- **Why it bites:** identical to #5 — older libstdc++ leaked these transitively;
  conda's newer libstdc++ does not → hard "not declared in this scope" errors.
- **Recipe workaround:** three IWYU patches that add the direct includes only
  (`patches/0002-add-algorithm-includes.patch`, `0003-add-cassert-includes.patch`,
  `0004-add-cstdint-limits-includes.patch`). Generated mechanically (`diff -u`,
  zero-fuzz) by inserting the include after each file's first `#include`. WERROR
  was also dropped (#2) via `0001-drop-WERROR.patch`, same as canvas (#6).
- **Suggested fix:** upstream IWYU audit of the whole suite; this keeps recurring.

## 10. TBB cross-product ABI coupling: art ↔ hep_concurrency `task_group` namespace

- **Where:** art's `Framework/Principal/Worker.cc` constructs
  `hep::concurrency::WaitingTaskList(tbb::task_group&)`. The exported/expected
  mangled symbol embeds TBB's versioned inline namespace
  (`tbb::detail::dN::task_group`), and **N bumps between oneTBB releases**
  (d1 in 2021.9 → d2 in 2023.0). So if art is compiled against a *different* TBB
  than `hep_concurrency` (#2) was, the link fails with an **undefined reference**
  to `WaitingTaskList(tbb::detail::d2::task_group&)`.
- **What triggered it:** following the skill's "use a `tbb-devel >=2021.9` FLOOR,
  not `==`" guidance, art's floor floated to **tbb 2023.0.0** while
  `hep_concurrency` was built against **2021.9** → mismatch → link error.
- **Resolution (this build):** pinned art to `tbb-devel 2021.9.*` to MATCH
  `hep_concurrency`. The `libtbb.so.12` *runtime* soname is stable across 2021.x,
  but this is a **compile-time C++ template-symbol** problem, not a runtime-soname
  one — soname stability does not save you here.
- **✅ RESOLVED at #9 (art_root_io + ROOT) — no rebuild needed.** conda-forge
  `root 6.28.10` does require `tbb >=2021.11`, so art_root_io's host solve floated
  to **tbb 2022.3.0**. Crucially, **art (built @2021.9) linked cleanly against
  tbb 2022.3.0**: oneTBB's `task_group` inline namespace is still `d1` at 2022.3 —
  the `d2` bump that caused the original undefined-reference was only introduced at
  **2023.0**. So a `tbb-devel >=2021.9` FLOOR (NOT `==2021.9`) is the right pin for
  the ROOT-era products: it floats up to ROOT's need while staying ABI-consistent
  with the 2021.9-built siblings. canvas_root_io (#7) already proved this vs canvas;
  #9 confirmed it vs art/hep_concurrency. The earlier #8 link failure was purely an
  artifact of an UNCAPPED floor reaching 2023.0 during a standalone art build (no
  root present to cap it) — pinning art's *build* to 2021.9 was the correct fix for
  building #8 in isolation, and does not constrain the final env (art's run_export
  is `tbb >=2021.9.0`, open-ceiling).

<!-- Add new findings above this line as the climb up the dep graph continues. -->
