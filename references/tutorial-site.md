# A tutorial site for a module (Quarto)

A module often needs more than its README: an introduction to the methods, with
worked examples. A Quarto website inside the module repository does that well —
multi-page, sidebar navigation, search, a bibliography — and, done as below, its
examples are computed by the module's own code, so the tutorial cannot disagree
with the module.

**Verified on 2026-09-27** building the jmsequential tutorial: Quarto 1.10.18
(the copy bundled with RStudio), R 4.6.1 arm64, macOS, inside a sandboxed agent
session.

## Examples computed by the module itself

This depends on the SKILL.md working style: compute in plain functions, free of
jmvcore. The site then loads the package source and calls those functions:

```r
# tutorial/_common.R, sourced by every page
pkgload::load_all("..", quiet = TRUE, export_all = TRUE,
                  helpers = FALSE, attach_testthat = FALSE)
```

- Set `execute-dir: project` in `_quarto.yml`. The default runs each page in its
  own directory, so `".."` would point somewhere different for pages in
  subfolders.
- `load_all` needs the package's `Imports` installed (jmvcore, R6), but it does
  not need the package to be built.

## Layout and what to version

```
tutorial/_quarto.yml  _common.R  references.bib  index.qmd  <section>/<page>.qmd
```

- Add `^tutorial$` to `.Rbuildignore`. `R CMD check` otherwise notes a
  non-standard top-level directory.
- Ignore `tutorial/_site`, `tutorial/.quarto`, `tutorial/**/*_files` and
  `tutorial/_freeze` in `.gitignore`.
- `_freeze` is regenerable and heavy: 5.8 MB for 20 figures × 2 renderings at
  192 dpi. Committing it adds that much to the history whenever a re-render
  changes the figures.
- With `execute: freeze: auto`, a page is re-executed only when **its own source**
  changes. A change to the module's `R/` code is invisible to it, so after
  changing the compute, run `rm -rf _freeze && quarto render`.

## Running Quarto in a sandbox

On macOS Quarto keeps its cache in `$HOME/Library/Caches/quarto`. In a sandbox
that cannot write there, every render dies before doing anything:
`PermissionDenied: Operation not permitted ... stat '.../Library/Caches/quarto'`.

- `XDG_CACHE_HOME` does not help. On darwin, `quarto.js` builds the path from
  `HOME` alone (`darwinUserCacheDir`, next to `quartoCacheDir` in `core/appdirs.ts`).
- The fix is to point `HOME` at a scratch directory. But R derives its user
  library and `~/.Rprofile` from `HOME` too, so both must be captured first.
- `scripts/quarto-sandbox.sh` does all of this. It also finds a Quarto when
  none is on `PATH`: it tries `quarto`, then the RStudio and Positron bundles.

      cd tutorial
      QUARTO_SCRATCH="$PWD/../.tmp/qhome" sh <skill>/scripts/quarto-sandbox.sh render

## Figures

- **Device.** Base `svg()` and cairo `png()` fail on a Mac without XQuartz
  (`cairo.so` links `/opt/X11/lib/libXrender.1.dylib`). Use ragg instead:
  `knitr::opts_chunk$set(dev = "ragg_png", dpi = 192, dev.args = list(bg = "transparent"))`.
  ragg is also in jamovi's base module library. A transparent background lets
  one PNG sit on either page theme.
- **Light and dark.** With `theme: {light: ..., dark: ...}`, the cell option
  `renderings: [light, dark]` (Quarto ≥ 1.7) shows the first plot in light mode
  and the second in dark mode. The cell must print exactly two plots. A helper
  that loops over both modes keeps each chunk to one call.
- **Do not put `label: fig-…` or `fig-cap` in a `renderings` cell.** Each
  rendering becomes its own numbered float. Measured: the same plot appeared as
  "Figure 1" (light) and "Figure 2" (dark), and every later number was shifted.
  Quarto documents the incompatibility. Wrap the cell instead:

      ::: {#fig-boundaries}
      ```{r}
      #| renderings: [light, dark]
      both(plot_function)
      ```
      Caption text.
      :::

## Screenshots of the panel

Pictures of the real options panel are captured by a script from jamovi in
Docker (`screenshots.md`), kept beside the tutorial in `screenshots/`, and
embedded as plain Markdown images with a figure id. They need no light/dark
renderings.

## References from DOIs

1. Verify each DOI against `https://api.crossref.org/works?query.bibliographic=...`.
2. Fetch the BibTeX with
   `curl -LH "Accept: application/x-bibtex; charset=utf-8" https://doi.org/<doi>`.
3. Clean what comes back:
   - HTML entities: `&amp;`, and `&lt;subtitle&gt;` inside titles;
   - inline tags: `<i>`, `<scp>`;
   - years: the year given is the *online-first* year (for example a 2011 volume
     cited as 2010), so override it with the print year;
   - author names in capitals (`FAIRBANKS`) and wrong casing (`Demets`).
4. Rename the keys to something readable (`pocock1977`).

## After rendering, check

- **Unresolved citations:** search the HTML for `?@`.
- **Broken links:** every internal `href="*.html"` resolves.
- **Figures:** each figure number appears once per figure.

The doubled figure numbers produced no warning at all, so a clean `quarto render`
log is not enough.
