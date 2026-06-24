# cetmodules → noarch + local channel — handoff

Date: 2026-06-24. Purpose: hand this to another session to **standardize the
dependents of cetmodules** against a single noarch cetmodules artifact served
from a local channel.

---

## 1. What we did (summary)

1. Converted the **feedstock** cetmodules recipe to `noarch: generic`.
2. Built it with `rattler-build`; the artifact landed in a `noarch/` subdir.
3. Registered it into a **local file:// channel** with `conda-index`, including
   empty `linux-64` / `osx-64` / `osx-arm64` subdirs so solvers on every
   platform find a valid subdir.

The recipe edited is:
`feedstocks/cetmodules-feedstock/recipe/recipe.yaml` (version **3.24.01**).

> NOTE: there is a *second*, older cetmodules recipe in this repo —
> `conda/recipes/art-suite/cetmodules/recipe.yaml`. See §6 (discrepancy) before
> standardizing — they install to **different paths**.

---

## 2. Why noarch is valid for cetmodules (verified)

cetmodules 3.24.01 contains **no compiled code**. We scanned the entire built
package with `file`: every artifact is a Perl/`.pm`, bash, or Python script
plus CMake modules. No ELF / Mach-O / PE / shared object / static archive
anywhere. Build deps are only `cmake` + `ninja` (no compiler). Therefore the
content is architecture-independent → `noarch: generic` is correct.

Key consequences of noarch (the mental model that drove the recipe shape):
- Recipe selectors (`if: unix`) are resolved at **build time on the build host**
  (linux), not at install time. A noarch package is rendered **once** and ships
  a single, frozen `depends` list to every platform.
- So an `else: __win` branch never lands in the artifact — it would only be
  selected by a dedicated windows render, which noarch never does.
- Windows exclusion is achieved by listing **`__unix`** in `run`: it is
  unsatisfiable on windows, so the solver cleanly refuses to install there,
  even though the package is visible in the universal `noarch/` subdir.

`checkClassVersion` is a **Python** script, so `python` was added to `run`.

---

## 3. Final recipe state (the parts that changed)

```yaml
build:
  noarch: generic          # was: skip: [win]
  number: 0

requirements:
  build:
    - cmake
    - ninja
    - sed                  # flattened (was: if: unix then sed)
  run:
    - bash
    - perl
    - python               # added — checkClassVersion is a Python script
    - __unix               # this is what blocks windows installs
```

Also flattened the now-always-true `if: unix` selector around
`make_bash_completions` in `tests:`.

`conda-forge.yml` keeps `noarch_platforms: linux_64` — now that the recipe IS
noarch this setting is meaningful (renders the single artifact on the linux
worker). It was inert while the recipe was platform-specific.

Verified from the built package's `info/index.json`:
`subdir=noarch`, `noarch=generic`, `depends=[bash, perl, python, __unix]`.

---

## 4. Build command (reproducible)

```bash
cd feedstocks/cetmodules-feedstock
rattler-build build --recipe recipe \
  --output-dir /nfs/data/1/calcuttj/wirecell_pixi_test/pixi-build-output
```

Artifact produced:
```
/nfs/data/1/calcuttj/wirecell_pixi_test/pixi-build-output/noarch/cetmodules-3.24.01-h5600cae_0.conda   (236 KiB)
```
(The other dirs in `pixi-build-output/` — `bld`, `linux-64`, `test`,
`src_cache` — are rattler-build scratch; only the `noarch/*.conda` matters.)

> We explored `pixi build` (pixi 0.70.2 supports `pixi build --path recipe.yaml`
> via the `pixi-build-rattler-build` backend) but **chose rattler-build** for
> this build. If a future session wants the native pixi-build path, that's the
> entry point.

---

## 5. The local channel

Location (persistent — keep it):
```
/nfs/data/1/calcuttj/wirecell_pixi_test/local-channel/
├── noarch/      cetmodules-3.24.01-h5600cae_0.conda + repodata.json
├── linux-64/    repodata.json (empty)
├── osx-64/      repodata.json (empty)
└── osx-arm64/   repodata.json (empty)
```

Created with:
```bash
CH=/nfs/data/1/calcuttj/wirecell_pixi_test/local-channel
mkdir -p "$CH/noarch" "$CH/linux-64" "$CH/osx-64" "$CH/osx-arm64"
cp .../pixi-build-output/noarch/cetmodules-3.24.01-h5600cae_0.conda "$CH/noarch/"
pixi exec --spec conda-index --spec python -- python -m conda_index "$CH"
```

**Re-index after adding/rebuilding any package** (otherwise repodata won't see
it):
```bash
pixi exec --spec conda-index --spec python -- python -m conda_index \
  /nfs/data/1/calcuttj/wirecell_pixi_test/local-channel
```

Consume it (channels listed highest-priority first):
```toml
# pixi.toml
channels = ["file:///nfs/data/1/calcuttj/wirecell_pixi_test/local-channel", "conda-forge"]
```
```bash
# conda/mamba
-c file:///nfs/data/1/calcuttj/wirecell_pixi_test/local-channel
```

---

## 6. Standardizing the dependents — what the next session needs to know

**Convention already in place:** every dependent recipe lists `cetmodules` in
`requirements.host:` (not `build`). Confirmed across:
`cetlib_except, cetlib, fhiclcpp, hep_concurrency, canvas, canvas_root_io,
messagefacility, art_root_io, art`. Standardize on `host:` — do not move it to
`build:`. (cetmodules is found via `find_package(cetmodules)` at configure time;
as a noarch package the same artifact is used regardless of target platform.)

**⚠️ Two cetmodules recipes exist with different install layouts — reconcile
before switching dependents:**

| recipe | installs CMake config to |
|---|---|
| `conda/recipes/art-suite/cetmodules/recipe.yaml` (older; dependents were built GREEN against this) | `lib/cetmodules/cmake/cetmodulesConfig.cmake` |
| `feedstocks/cetmodules-feedstock/recipe/recipe.yaml` (the noarch one we just built) | `share/cetmodules/cmake/cetmodulesConfig.cmake` |

The feedstock recipe applies `namespace-install-paths.patch`, which is why its
layout differs (share/ vs lib/). Before repointing dependents at the noarch
artifact, **verify `find_package(cetmodules)` still resolves** with the `share/`
layout — cetmodules' own config search path must cover it. If a dependent fails
to find cetmodules after the switch, this layout difference is the first
suspect, not a rattler/pixi bug.

**Suggested standardization steps for the next session:**
1. Decide which cetmodules recipe is canonical (recommend the noarch feedstock
   one) and retire/align the other so there is a single source of truth.
2. Confirm `find_package(cetmodules)` resolves against the canonical layout in
   one dependent (e.g. `cetlib_except`, the leaf) before doing the rest.
3. Point every dependent's `host: cetmodules` at the local channel above,
   rebuild in dependency order, re-index the channel after each, and confirm
   the art stack stays green.
4. Keep `cetmodules` unpinned or pin consistently across all dependents — pick
   one policy.

---

## 7. Open question carried over

`python` is currently an **unpinned** run-dep of cetmodules (added for
`checkClassVersion`). It's safe and almost certainly already present in any art
env, but the next session may want to confirm `checkClassVersion` is actually
exercised by the dependents' ROOT-dictionary builds and pin/scope accordingly.
