# art v3_14_04 — conda packaging plan

Status as of 2026-06-19. Goal: build FNAL **art v3_14_04 + ROOT I/O** as
**rattler-build conda packages**, managed by pixi. LArSoft is out of scope.

## BUILD PROGRESS (climbing the dep table below)
- [x] **#0 cetmodules** 3.24.01 — GREEN. `noarch`, FNALssi dotted tag, needs
  `--allow-symlinks-on-windows`. Artifact in `art-suite-output/noarch/`.
- [x] **#1 cetlib_except** 1.09.01 — GREEN. Validated the cetmodules-consumer
  CMake pattern end-to-end (cetmodules from local channel). `-Werror` did NOT
  bite. host deps: `cetmodules` + `catch2 3.3.*` (catch2 needed at configure —
  see `potential_improvements.md`). Config installs to `lib/<proj>/cmake/`.
  `recipes/art-suite/cetlib_except/{recipe.yaml,build.sh,variants.yaml}` is the
  template for the remaining compiled C++ products.
- [x] **#2 hep_concurrency** 1.09.02 — GREEN. First sibling link (cetlib_except
  from local channel) + first external link (TBB / `tbb-devel 2021.9.*`). catch2
  NOT needed (test-only). `-Werror` clean. No LICENSE in tarball.
- [x] **#3 cetlib** 3.18.02 — GREEN. boost (regex/program_options/filesystem,
  pinned `libboost-devel 1.85.*` to match WCT), libsqlite, openssl, cetlib_except.
  `-Werror` clean even on the big surface. OpenSSL was undeclared in product_deps
  (potential_improvements #4).
- [x] **#4 fhiclcpp** 4.18.04 — GREEN (needed a patch). cetlib + tbb + transitive
  cetlib closure (boost/sqlite/openssl/cetlib_except via find_dependency). First
  failure→patch→green: missing `#include <cassert>` in DatabaseSupport.cc
  (`patches/0001-...`, potential_improvements #5). `-Werror` itself clean.
- [x] **#5 messagefacility** 2.10.05 — GREEN, no patch. fhiclcpp+cetlib+cetlib_except
  +boost, and Catch2 is UNCONDITIONAL+EXPORT here (host catch2 3.3.*, propagates).
  lib MF_MessageLogger; script fix-mf-macros.
- [x] **#6 canvas** 3.16.04 — GREEN (needed a patch). clhep + range-v3 + boost
  date_time + full sibling closure. FIRST time `-Werror` bit: RangeSet.cc ignores
  std::unique's [[nodiscard]] result; dropped WERROR (`patches/0001-drop-WERROR.patch`,
  potential_improvements #6) rather than alter logic. All pure-C++ products done.
- [x] **#7 canvas_root_io** 1.13.05 — GREEN. First ROOT product. Fix for the
  README/ROOT-dir collision: `cet_cmake_env(NO_INSTALL_PKGMETA)` via
  `patches/0002-no-install-pkgmeta.patch` (see potential_improvements #7); plus
  `-D_CheckClassVersion_ENABLED=FALSE` (#8). NOT a rattler bug (was misdiagnosed).
- [x] **#8 art** 3.14.04 — GREEN (4 patches). Largest product; full sibling
  closure (canvas/hep_concurrency/messagefacility/fhiclcpp/cetlib(_except)) +
  CLHEP/Range-v3/TBB/Boost. Patches: `0001-drop-WERROR` (VIGILANT+WERROR, same as
  canvas), `0002-add-algorithm-includes` (11 files, std::any_of/find_if w/o
  `<algorithm>`), `0003-add-cassert-includes` (22 files), `0004-add-cstdint-limits`.
  **TBB pin = `2021.9.*` (NOT a floor):** art links hep_concurrency's
  `WaitingTaskList(tbb::detail::dN::task_group&)` — the versioned inline namespace
  bumps between TBB releases, so a `>=2021.9` floor floated to 2023.0 and gave an
  undefined-reference link error vs the 2021.9-built hep_concurrency. See
  potential_improvements.md #9 (includes) and #10 (TBB ABI + ⚠ ROOT tension).
  Built execs: art/gm2/lar/nova. Artifact in `art-suite-output/linux-64/`.
- [x] **#9 art_root_io** 1.13.05 — GREEN (first build, no failed iterations).
  FINAL product: ROOT event I/O for art (RootInput/RootOutput/TFileService +
  art's ROOT dictionaries). Combines ROOT (#7 pattern) with the full art
  framework (#8). 3 patches: `0001-drop-WERROR`, `0002-no-install-pkgmeta`
  (README-vs-ROOT-dir, same as #7), `0003-add-standard-includes` (23 files:
  algorithm/cassert/cstdint/limits, computed per-file in one patch). build.sh
  uses `_CheckClassVersion_ENABLED=FALSE` (PyROOT sandbox, #7/#8). Execs:
  product_sizes_dumper/config_dumper/count_events/file_info_dumper/
  sam_metadata_dumper. Artifact in `art-suite-output/linux-64/`.
  **TBB-vs-ROOT tension RESOLVED (empirically):** host solve gave root 6.28.10 +
  **tbb 2022.3.0**, and art (built @2021.9) linked cleanly against it — oneTBB's
  task_group inline namespace is still `d1` at 2022.3 (the `d2` bump that broke
  the #8 link was only at 2023.0). No rebuild of hep_concurrency/art needed; the
  `tbb-devel >=2021.9` float (NOT `==`) is correct for the ROOT-era products.
  See pot._impr. #10.

**🎉 STACK COMPLETE — all of #0–#9 (art v3_14_04 + ROOT I/O) are GREEN.**
Remaining follow-ups (NOT blockers): (1) ~~licenses batch pass~~ ✅ DONE
2026-06-19 (all 10 recipes declare `license: BSD-3-Clause` + `license_file:
LICENSE`; the two tarballs that omit LICENSE — hep_concurrency, art_root_io —
get a vendored copy in the recipe dir; see pot._impr. #3); (2) `wct_downstream`
rebuild was deferred earlier.

**⏸ PARKED TODO — incomplete conda RUN-dependency graph (run_exports).**
Validated 2026-06-19 via an end-to-end pixi env on `art_root_io`: it solved/
installed, but the runtime closure pulled in ONLY external leaf deps (clhep/
boost/sqlite/tbb) — **not root, and not any art-suite sibling** (art, canvas,
canvas_root_io, cet*). Cause: recipes have empty `run:` sections and rely on
run_exports, but our cet*/art recipes define none, so nothing propagates. The
*build* graph is correct and complete (suite builds + links fine); only the
*run* graph is empty. Upstream is fine — `product_deps` declares the full
hierarchy; we just didn't translate it.
- **Fix mechanism (clear, larsoft-agnostic):** add `build.run_exports:
  - ${{ pin_subpackage(name, upper_bound=...) }}` to each RUNTIME library
  (cetlib_except/cetlib/fhiclcpp/hep_concurrency/messagefacility/canvas/
  canvas_root_io/art/art_root_io) — NOT cetmodules (noarch build system) or
  test-only deps — plus explicit `run: - root 6.28.10.*` on the two ROOT
  products. Then re-run the pixi solve; it should pull art+root+all siblings.
- **Why PARKED (decision 2026-06-19):** the *policy* — run_export pin tightness,
  whether a metapackage/bundle is the intended install target, root pinning across
  the stack — is best dictated by LarSoft (the next integration target and the
  actual top of the hierarchy; `art_root_io` is a MIDDLE layer, not the top).
  Settle run_exports when scoping larsoft rather than guessing now + rebuilding
  twice. Full rationale: memory `conda-run-exports-policy`.
- Validation scaffold left in scratchpad: `…/scratchpad/art-validate/pixi.toml`
  (channels = local art-suite-output + conda-forge, dep = art_root_io).
- Side note: the local channel `repodata.json` had to be hand-patched after the
  license rebuilds overwrote .conda files (rattler-build didn't refresh the
  sha256/size on same-name overwrite). A `.bak` sits beside each repodata.json.

Reusable build invocation (from `conda/`):
`rattler-build build --recipe recipes/art-suite/<pkg>/recipe.yaml -c ./art-suite-output -c conda-forge --allow-symlinks-on-windows`

**LICENSES — ✅ DONE (2026-06-19, batch step after the suite built).** All 10
products declare `license: BSD-3-Clause` + `license_file: LICENSE`. The FNAL BSD
text is byte-identical across the suite; hep_concurrency and art_root_io omit it
upstream so a vendored copy lives in their recipe dirs. (Originally deferred per
user: don't hunt licenses while building — revisited together once green.) See
`potential_improvements.md` (#3).

## Decisions locked in
- **Packaging style:** rattler-build conda packages (one recipe per product),
  mirroring the existing `recipe/` WCT recipe conventions — NOT source-build pixi tasks.
- **Scope:** full art *plus* ROOT event I/O (canvas_root_io + art_root_io + ROOT).
- WCT itself is already rebuilt/installed after the dir move (done earlier today);
  `wct_downstream` rebuild was deferred.
- Ignore `~/fetch.txt` / apptainer route (user said drop it). GitHub raw +
  conda-forge are sufficient.

## Resolved dependency graph (AUTHORITATIVE — from each repo's ups/product_deps)

From-source products, in build/dependency order. Most repos live at
`github.com/art-framework-suite/<repo>`; tags use underscores; multiword repo
names hyphenate (`fhicl-cpp`, `hep-concurrency`, `canvas-root-io`, `art-root-io`).
Tarball URL pattern: `https://github.com/art-framework-suite/<repo>/archive/refs/tags/<TAG>.tar.gz`

EXCEPTION — **cetmodules** is at `github.com/FNALssi/cetmodules`, NOT
art-framework-suite, and its git tags use **dotted** form (`3.24.01`), not the
UPS `v3_24_01`. Archive (verified, byte-stable, extractable):
`https://github.com/FNALssi/cetmodules/archive/refs/tags/3.24.01.zip`
sha256 `9f66df000cc44ea775fb6d36bff075aa5fbf055e910ed064bf0729a35d30e9d1`.
Source zips are staged locally under `<project-root>/src_bundles/` as a fallback.
Watch for the same FNALssi-vs-art-suite / dotted-vs-underscore split on the
other low-level cet* products when you reach them.

| # | product         | TAG        | repo            | non-build deps                  |
|---|-----------------|------------|-----------------|---------------------------------|
| 0 | cetmodules      | v3_24_01   | cetmodules      | (build system; build FIRST)     |
| 1 | cetlib_except   | v1_09_01   | cetlib-except   | —                               |
| 2 | hep_concurrency | v1_09_02   | hep-concurrency | cetlib_except, tbb              |
| 3 | cetlib          | v3_18_02   | cetlib          | cetlib_except, boost, sqlite    |
| 4 | fhiclcpp        | v4_18_04   | fhicl-cpp       | cetlib, tbb                     |
| 5 | messagefacility | v2_10_05   | messagefacility | fhiclcpp                        |
| 6 | canvas          | v3_16_04   | canvas          | clhep, messagefacility, range   |
| 7 | canvas_root_io  | v1_13_05   | canvas-root-io  | canvas v3_16_04, root v6_28_10b |
| 8 | art             | v3_14_04   | art             | canvas, hep_concurrency         |
| 9 | art_root_io     | v1_13_05   | art-root-io     | art v3_14_04, canvas_root_io v1_13_05 |

Build-only/test deps recurring across the suite: cetmodules (above),
catch v3_3_2 (= conda-forge `catch2` 3.3.x), range v3_0_12_0 (= `range-v3` 0.12.0).

## conda-forge externals — all pinned versions CONFIRMED available
- root **6.28.10** (also 6.28.12 exists; v3_14 chain wants 6_28_10b → use 6.28.10)
- boost 1.82.0 → use `libboost-devel 1.82.*` (see WCT recipe note re: boost name/runtime)
- tbb / tbb-devel **2021.9.0**
- sqlite **3.40.0**
- range-v3 **0.12.0**
- clhep **2.4.7.2** (pin is .1; .2 is a patch bump, expected fine)
- catch2 **3.3.x** (build/test only)

## Key technical risk / approach
art-suite are CMake projects that `find_package(cetmodules)` and use its macros
(`cet_cmake_env()`, `cet_make_library()`, …), and they locate each other via
generated `<pkg>Config.cmake`. They must be built in cetmodules **non-UPS mode**
(cetmodules 3.x supports this; spack does the same). Downstream packages find
their already-installed siblings via `CMAKE_PREFIX_PATH=$PREFIX`.
Unknowns to resolve empirically while doing step 1 below:
- exact cmake invocation / env cetmodules wants outside UPS (CETMODULES_* vars?).
- whether boost 1.85-style API drift bites cetlib/canvas (WCT hit boost issues).
- whether ROOT 6.28.10 conda build provides what canvas_root_io's dictionary
  generation needs (rootcling, the cmake ROOT config).

## Tooling status
- `rattler-build` 0.66.2 available at `~/.pixi/bin/rattler-build`. ✅
- Existing reference recipe: `recipe/recipe.yaml` + `recipe/build.sh` +
  `recipe/variants.yaml` (WCT). Reuse its structure: `${{ compiler('c'/'cxx') }}`,
  `${{ stdlib('c') }}`, `variants.yaml` with sysroot 2.17, package_contents tests.

## PLAN — pick up here tomorrow

**Step 0 — layout.** Create `recipes/art-suite/<pkg>/` dirs (one per product),
each with `recipe.yaml` + (if needed) `build.sh`. Keep a top-level note of the
build order. Consider a small driver script that builds them in order and feeds
each one's output back as a local channel for the next
(`rattler-build build ... ` then `-c ./output -c conda-forge`).

**Step 1 — get cetmodules green FIRST (validates the whole approach).**
  - Was just about to: fetch `cetmodules/v3_24_01/CMakeLists.txt` to see how it
    bootstraps, and `sha256sum` the tarball
    (`https://github.com/art-framework-suite/cetmodules/archive/refs/tags/v3_24_01.tar.gz`).
  - Write `recipes/art-suite/cetmodules/recipe.yaml`: plain CMake configure/build/
    install into `$PREFIX`. host deps minimal (cmake, python). It installs cmake
    modules + python; likely `noarch`-ish but treat as generic.
  - `rattler-build build --recipe recipes/art-suite/cetmodules/recipe.yaml`.
  - Iterate until it produces a `.conda`. This proves the cetmodules-non-UPS path.

**Step 2 — climb the table in order (1→9).** For each: write recipe.yaml +
build.sh (cmake using cetmodules from the local channel + conda-forge externals),
build with `-c <local-output-dir> -c conda-forge`, add `package_contents` tests
(libs/headers), fix failures before moving on. cetlib_except (1) is the smallest
real C++ package — use it to nail the cetmodules-consumer cmake invocation, then
the rest are mechanical variations.

**Step 3 — ROOT-dependent links (7, 9).** Watch ROOT 6.28.10 dictionary gen.

**Step 4 — integrate into pixi.** Add tasks to `pixi.toml` to build the suite
(and/or add the produced packages as deps), parallel to the WCT tasks.

**Step 5 — smoke test.** `art --version`; run a trivial fhicl through `art`.

## Useful verified facts
- product_deps fetch that works:
  `curl -sL https://raw.githubusercontent.com/art-framework-suite/<repo>/<TAG>/ups/product_deps`
- GitHub tags API: `https://api.github.com/repos/art-framework-suite/<repo>/tags?per_page=100`
- scisoft.fnal.gov dir listings return the web wrapper / 403 — don't use.
- Memory written: `art-v3_14_04-dep-graph` (in project memory) holds this graph.
