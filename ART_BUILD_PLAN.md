# art v3_14_04 — conda packaging plan

Status as of 2026-06-18. Goal: build FNAL **art v3_14_04 + ROOT I/O** as
**rattler-build conda packages**, managed by pixi. LArSoft is out of scope.

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
