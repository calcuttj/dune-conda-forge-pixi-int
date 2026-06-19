# art-suite conda packaging — current status

_Updated 2026-06-19. See `ART_BUILD_PLAN.md` (plan/dep-graph), `potential_improvements.md`
(upstream warts), and the `package-art-product` skill (per-product procedure)._

## Progress: 8 of 10 products green (build → output channel `conda/art-suite-output/`)

| # | product | status | notes |
|---|---------|--------|-------|
| 0 | cetmodules 3.24.01 | ✅ `_1` | noarch; `_1` strips stray `$PREFIX/{INSTALL,LICENSE,README}` (collided w/ ROOT) |
| 1 | cetlib_except 1.09.01 | ✅ `_1` | `_1` strips stray `$PREFIX/{INSTALL,LICENSE,README}` |
| 2 | hep_concurrency 1.09.02 | ✅ `_0` | tbb |
| 3 | cetlib 3.18.02 | ✅ `_2` | `_1` pins `openssl >=3.2,<4.0a0` (ROOT compat); `_2` strips prefix-root docs |
| 4 | fhiclcpp 4.18.04 | ✅ `_2` | patch: `#include <cassert>`; `_1` drops openssl from host; `_2` strips prefix-root docs |
| 5 | messagefacility 2.10.05 | ✅ `_1` | catch2 unconditional; `_1` drops openssl from host |
| 6 | canvas 3.16.04 | ✅ `_1` | patch: drop `-Werror`; `_1` drops openssl from host |
| 7 | canvas_root_io 1.13.05 | ✅ `_0` | first ROOT product; patch `0002-no-install-pkgmeta` (see below) + `_CheckClassVersion_ENABLED=FALSE` |
| 8 | art v3_14_04 | ⬜ TODO | |
| 9 | art_root_io v1_13_05 | ⬜ TODO | also builds ROOT dictionaries → needs `_CheckClassVersion_ENABLED=FALSE`, and `NO_INSTALL_PKGMETA` like #7 |

Channel was fully rebuilt from a pristine cache (`./rebuild_art_suite.sh --fresh`);
it holds exactly one build of each product (the numbers above). Lower products use
strip-after-install for the prefix-root docs (works because ROOT isn't in their env);
#7 uses `NO_INSTALL_PKGMETA` (the proper fix) — see below and potential_improvements #7.

## canvas_root_io (#7): RESOLVED ✅

Recipe at `recipes/art-suite/canvas_root_io/`; all sub-issues solved:
1. ✅ rattler needs a range specifier: `root 6.28.10.*` (not `root 6.28.10`).
2. ✅ openssl soname clash: ROOT needs `openssl <4`. Fixed by pinning openssl 3.x in
   cetlib (`_1`) and removing openssl from the other recipes' host (transitive via cetlib).
3. ✅ tbb floor: ROOT needs `tbb >=2021.11`; recipe uses `tbb-devel >=2021.9` (oneTBB
   2021.x is ABI-stable; cet* run_exports `>=2021.9.0` no ceiling).
4. ✅ checkClassVersion (PyROOT) fails in sandbox → disabled via
   `-D_CheckClassVersion_ENABLED:BOOL=FALSE` in build.sh (potential_improvements #8).
5. ✅ **The README/ROOT collision (the long blocker) — see potential_improvements #7.**

### The blocker that ate this session, and how it was actually fixed
ROOT (`root_base`) ships `$PREFIX/README` as a **directory** (`README/ReleaseNotes/…`).
cetmodules' `cet_cmake_env()` auto-installs the product's top-level `README` **file**
via `install_pkgmeta()`. When canvas_root_io builds (ROOT already in its host env),
cmake installs our README file over ROOT's README **directory**, dropping the file
inside it AND chmod'ing the **directory** to 0644 (loses `+x`); rattler-build's
post-build step then can't traverse `README/` → `Permission denied (os error 13)`.
(Before the lower-product README strips, the same collision surfaced as link-time
`ENOTDIR (os error 20)`.)

This was **misdiagnosed as a rattler-build bug** (a supposed read-only/0644 dir-link
defect) and nearly filed upstream. It is NOT: a fully pristine-cache rebuild still
reproduced it, proving the cause is our own install, not accumulated state or rattler.

**Fix:** `patches/0002-no-install-pkgmeta.patch` → `cet_cmake_env(NO_INSTALL_PKGMETA)`,
which suppresses the doc auto-install so ROOT's directory is never touched. #7 builds
green: `art-suite-output/linux-64/canvas_root_io-1.13.05-h41f06ac_0.conda`.
Use `check-prefix-collisions` skill to audit; expect the same at #9 art_root_io.

Strip-after-install does NOT work here (chmod already done during install; can't `rm`
ROOT's directory) — that approach only works for the lower products where ROOT is
absent from the host env.

## Environment / how to build
- `export RATTLER_CACHE_DIR=/nfs/data/1/calcuttj/.cache/rattler`
  `PIXI_CACHE_DIR=/nfs/data/1/calcuttj/.cache/rattler` (also set in `.claude/settings.json`).
- From `conda/`:
  ```
  ~/.pixi/bin/rattler-build build --recipe recipes/art-suite/<pkg>/recipe.yaml \
    --output-dir ./art-suite-output -c ./art-suite-output -c conda-forge \
    --allow-symlinks-on-windows > <log> 2>&1; echo "RATTLER_EXIT:$?" >> <log>
  ```
  (Capture exit INTO the log — a piped `echo`/`tail` masks rattler's real status.)
- rattler-build 0.66.2 at `~/.pixi/bin/rattler-build`.
