# Building, installing and shipping

## The commands

| command | does |
|---|---|
| `jmvtools::prepare()` | regenerates `.h.R`, `00jmv.R`, `0000.yaml`, `build/js/*.src.js` from the yamls |
| `jmvtools::install()` | prepare + `R CMD INSTALL` + bundle dependencies + write `<Module>.jmo` + install into jamovi |
| `jmvtools::check()` | validates module structure |
| `jmc` | the same compiler as a CLI — what you use inside a container |

`jmvtools` builds *for jamovi*; `devtools` builds *for R*. Use `devtools::test()`
for the suite, `jmvtools::install()` for the app.

## `jmvtools::install()` lies about failure

**It reports compiler and version errors on stdout and still exits 0.** Worse:
when the environment cannot take jamovi.app's SingletonLock (a sandbox, a
concurrent instance) it prints `Failed to create SingletonLock` and then
`Module installed successfully` having installed nothing at all.

Never trust the exit status or the success line. Verify by listing the installed
module directory and checking its timestamp, or by asserting on a file you know
the build should have produced.

## jmvtools must match the installed jamovi

`jmc` asks the app given to `--home` (or `/Applications/jamovi.app`) for its
version before *any* command, `--prepare` included (`installer.js:check()`).
From jmvtools 28.4, a jamovi between 28.0 and 28.3 is rejected with
`jamovi 28.4 or newer is required`. 28.4 is when the File control was renamed,
and a module compiled by one side does not work on the other. jamovi 2.x
(solid) still passes. In practice:

- updating jmvtools (repo.jamovi.org had 28.4 on 2026-09-30) stops every
  build against a 28.3 `jamovi.app` until the app is updated too;
- the `current` series of `build-jmo.sh` stamps whatever the app says, so
  build only after the app update;
- the docker image (`jamovi/jamovi:<series>`) carries its own matching `jmc`,
  so `install.sh docker` is unaffected once the image is rebuilt.

## Things that fail silently at build time

- **`R CMD INSTALL` does not recurse into `R/` subdirectories.** `R/vendored/x.R`
  is not installed — no error, just a missing function at runtime. Keep `R/`
  flat: `R/vendored_x.R`.
- **`.gitignore` and `.Rbuildignore` are independent lists.** A working
  directory ignored by git is still rolled into `R CMD build`. One jamovi source
  clone sitting beside a module accounted for **3714 of 3809 files and 14 of
  14 MB** of the tarball, and three of five `R CMD check` WARNINGs. Add every
  working directory to both, and remember that a root-level pattern
  (`^2026-.*\.md$`) stops matching once the files move into `docs/`.
- **`NAMESPACE` is hand-maintained the moment any of it is.** If most entries
  have no roxygen tag, `roxygenise()` will *delete* them rather than reproduce
  them. Drop `RoxygenNote:` from DESCRIPTION and say so in a header comment.
  Note jamovi reaches your analysis through
  `namespace[[paste0(name, "Class")]]` (`jmvcore::create`), which bypasses the
  export list entirely — so a module needs no exports at all, and adding them
  only obliges you to document an interface that may not be usable from R.

## The tools/ template — every module starts with it

`templates/tools/` holds the build, install and release scripts every module in
this collection uses. Copy them in with

    sh <skill>/scripts/add-tools.sh <repo-root>        # --force to refresh

They need no editing. `_module.sh`, sourced by all of them, finds the module —
the repository root, or the one subfolder holding `DESCRIPTION` and `jamovi/` —
and reads `Package` and `Version` from `DESCRIPTION`. The only per-module file
is `tools/smoke.R`, which the copier never overwrites.

| script | does |
|---|---|
| `build-jmo.sh {current\|solid}` | `jmc --build --home <app> --jmo`, stamped from that app's `env.conf`, then `prepare-jmo.sh` |
| `prepare-jmo.sh` | repacks one build into the x64 and arm64 artifacts in `dist/`; refuses a `.jmo` with native libraries |
| `install.sh [desktop\|docker\|both]` | `jmvtools::install()` into jamovi.app and/or `jmc --install` into the container, then runs `tools/smoke.R` against the installed copy |
| `release.sh [--prune]` | builds both series and publishes the four artifacts as one `v<version>` GitHub release |
| `smoke.R` | the module's own check: call one analysis and `stop()` on a wrong answer |

Verified on 2026-09-27 with jmsequential on the arm64 Mac:

- `build-jmo.sh current` and `build-jmo.sh solid` wrote all four artifacts;
- `install.sh docker` installed into jamovi 28.1 and passed the module's smoke test;
- `install.sh desktop` detected the sandboxed-Electron failure and printed the sideload
  path.

`install.sh` already handles three traps described below:

- the `SingletonLock` / sandboxed-Electron failure. The `.jmo` is built, so the
  script says to sideload it rather than failing.
- the unreadable `~/.docker/config.json`. The script uses a writable
  `DOCKER_CONFIG` under `.tmp/`.
- `--skip-deps`. It is the default; set `JMC_SKIP_DEPS=no` for a module whose
  dependencies jamovi does not bundle.

## Dependencies

jamovi resolves module dependencies from a **frozen CRAN snapshot**, taken at
the start of each jamovi series and moved forward every 6–12 months. Two
consequences:

- A package that disappears from CRAN, or is marked obsolete, means your module
  **fails to install** — not merely degrades. Prefer base R; reimplementing four
  functions from their published definitions has been the cheaper path here more
  than once.
- A package version newer than the snapshot needs `Remotes:` in DESCRIPTION
  pinned to a commit. Use sparingly: it can conflict with the same package in
  another module.

Declare everything you use under `Imports:` and call it with `::`. Relying on
"jmvcore imports it anyway" works until it doesn't, and `::` also gives lazy
loading, which keeps jamovi's memory down. No `Depends:`.

Deployment environments can be stricter than your laptop: on one HPC cluster
runtime package installation fails outright (`openat2()` ENOSYS on kernel 4.18),
so anything not bundled at build time is simply unavailable.

## Testing against a real jamovi

Two beds, and the container is the better one:

- **Desktop** — fastest loop, but the install can silently no-op (above), and
  jamovi.app cannot be driven while it is already open: `jmvtools::install()`
  then reports `SingletonLock` *and* a success line. The `.jmo` is still built,
  so treat that case as "built, not installed" and carry on rather than
  aborting — anything your script must do to the source tree (re-applying a
  generated-file patch, say) has to happen **before** that early exit, or a
  locked run leaves the tree broken.
- **Docker** (`jamovi/jamovi:<series>`) — `jmc --install` into a running
  container works reliably and is how Linux and cloud behaviour get tested.
  Bootstrap `jmc` and node in the container once; they survive `docker restart`
  but not `compose down/up`.

Keep one install script that does both, taking `[desktop|docker|both]`, and
have each target **skip cleanly** when its bed is unavailable so `both` still
succeeds on a machine with only one.

**Assert the invariants you actually depend on** — the `.jmo`'s contents, the
version in the installed `jamovi.yaml`, a smoke-test analysis run — rather than
trusting the tool's output. Do *not* assert "the ui js exists under the
lowercased name": that was in this file for a while and it is not an invariant
(SKILL.md).

Two environment traps that have each burned an afternoon:

- **A sandboxed shell may fail `docker` for a reason that has nothing to do
  with docker.** If `~/.docker/config.json` is unreadable the CLI prints
  `WARNING: Error loading config file … operation not permitted` and returns
  nothing, so a `docker ps | grep <container>` check concludes the container is
  not running. Point `DOCKER_CONFIG` at a writable directory and it works.
  Confirm the bed is really absent before reporting a target as untestable.
- **`core.fileMode = false`** in a repo makes git record no mode change, so
  scripts commit as `100644` and arrive non-executable for everyone cloning.
  Set it per file with `git update-index --chmod=+x`.

## `R CMD check`

A jamovi module cannot reach 0 WARNINGs. Ours sits at three, all inherent:
non-ASCII characters in `.R`, undocumented compiler-generated exports, and a
`.tsv` in `data/`. **Write down which ones are expected**, because the value of
check is entirely in the fourth one appearing.

- `data/` is where bundled datasets must live — jmvtools copies them out of the
  *installed package's* `data/` into the `.jmo`, so `inst/extdata` (which check
  prefers) does not work. Converting a `.tsv` to `.csv` makes it a recognised R
  dataset and then demands its own `.Rd`; leave it.
- ggplot2 NSE column names produce "no visible binding" NOTEs — silence them
  with `utils::globalVariables()`, not by importing what check suggests.

## Shipping

A `.jmo` is specific to **OS × architecture × jamovi series** (solid/current) —
eight combinations. Side-loading to a colleague usually fails unless their setup
matches exactly. That is what the library is for: submit the *source* and the
jamovi team builds all platforms.

Before submitting to the library:

- Distinctive module name, **no dot in it** (jamovi will not load it), not
  generic, not containing "jamovi". Renaming later touches `0000.yaml`,
  `DESCRIPTION` and every filename.
- An OSI-approved licence in DESCRIPTION (GPL2+ recommended; AGPL3 is not
  accepted). If you bundle a GPL R package, the combined work must be GPL.
- English at minimum; other languages optional.
- Bundled example dataset(s) registered under `datasets:` in `0000.yaml`, small
  and containing **no** personal or confidential data.
- Input checks that survive missing data, odd variable names, and an empty
  dataset.
- No build artefacts committed (`build/`, `dist/`, `*.jmo`).
- Version bumped in **both** `0000.yaml` and `DESCRIPTION`.

Submit by email to contact@jamovi.org with a link to the source repository.
Review takes 1–2 weeks and usually comes back with comments. Updates: bump,
push, tell them; the library rebuilds weekly.

If you keep design notes, audits and benchmarks in the repo, put them in a
gitignored working directory so the tree a reviewer clones is the module and
nothing else — and then make sure no shipped source comment *cites* those files,
or it is a dangling reference to a reader who cannot see them.
