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

- **Desktop** — fastest loop, but the install can silently no-op (above), and a
  case-insensitive filesystem hides the lowercase-js bug entirely.
- **Docker** (`jamovi/jamovi:<series>`) — `jmc --install` into a running
  container works reliably, is the only way to see Linux/case-sensitive
  behaviour, and is how cloud behaviour gets tested. Bootstrap `jmc` and node in
  the container once; they survive `docker restart` but not `compose down/up`.

Keep an install script that does both and **asserts the invariants** (file
casing, the `.jmo` contents, the presence of the ui js under the lowercased
name) rather than trusting the tool's output.

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
