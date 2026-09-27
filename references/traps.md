# The checklist

One line each, grouped by when it bites. Everything here is expanded, with
evidence, in the other reference files. Verified against jamovi 28.1 /
jmvtools 28.3 / jmvcore 2.7.38.

## Naming and layout

- [ ] Files in `jamovi/` are **lower case**; the analysis name inside the yaml is not.
      (Convention, for internal consistency — *not* the Linux panel bug this
      file used to claim. See SKILL.md; camelCase ships fine on jamovi 28.x.)
- [ ] `R/` is **flat** — `R CMD INSTALL` does not recurse into subdirectories, and it does not warn.
- [ ] No private R6 member called `.data` (or any other jmvcore `Analysis` private name).
- [ ] The module name has **no dot** in it, and is not generic ("Statistics") or "jamovi"-ish.

## Results structure

- [ ] Every table row **and column** that must survive a click is created in `.init()`.
- [ ] `.init()` is cheap — it runs on every option click, on top of an unchanged UI.
- [ ] `rowCount`/`isNotFilled()` gate *writing rows*, never *recomputing*; use `setState()` for that.
- [ ] `addRow` in a loop is quadratic — pre-size in `.init()` and `setRow()` in `.run()`.
- [ ] Hidden tables cost exactly what visible ones cost; don't build rows for a table nobody sees.
- [ ] Every element that must survive an unrelated click has an explicit `clearWith`.
- [ ] Row keys are compared strictly: `addRow(rowKey = 1)` followed by `setRow(rowKey = 1L)` fails with "rowKey '1' not found". Build both from the same `seq_len()` / integer values.
- [ ] Every option a `renderFun` reads is listed in that Image's `clearWith`.
- [ ] Plot data lives in `image$state` (or `requiresData: true`), never in an R6 field — the image-save path never calls `.run()`.
- [ ] Image state is set only when absent, or every plot re-renders on every click.
- [ ] `ggtheme` is a **list** (theme + two palette scales): `ggtheme + theme(...)` is silently `NULL`, and adding the list replaces the plot's own scales.
- [ ] `geom_text` colour does not follow the theme — take it from `calc_element("text", ...)`.
- [ ] Run-phase notes are set with `init = FALSE`, and stale placeholder keys are re-declared in `.init()`.
- [ ] Cached state stays well under **500 000 compressed bytes** (`jmvcore/R/results.R:223`).
- [ ] `type: Notice` in `.r.yaml` **does not compile**; build `jmvcore::Notice$new()` and `results$insert()`.
- [ ] `type: Notification` compiles and then dies at runtime with "attempt to apply non-function".
- [ ] A dynamically inserted element has no `self$results$<name>` binding — reach it with `$get("name")`.
- [ ] Status messages never hardcode a colour; the dark theme makes it unreadable.

## Data in and out

- [ ] `weightsSupport` is declared, not inherited: the fallback is `none` with an `Output` option and `auto` without, and `auto` replicates rows so `nrow(self$data)` is the sum of the weights.
- [ ] Convert types (`jmvcore::toNumeric`, `as.factor`) **before** `na.omit()`/`subset()` — they strip jamovi's attributes.
- [ ] Output columns: `setRowNums(rownames(data))`, never `1:nrow(data)` — silently wrong under any filter.
- [ ] Output columns that must **grow** the dataset: do not call `setRowNums` at all.
- [ ] Output columns carry integers (+levels) or doubles only; character vectors are auto-factored.
- [ ] An `Output` option cannot default to ticked — design the UX (and a warning) around that.
- [ ] Within one analysis, an output key you stop emitting **deletes** its column; deletion is only safe in a message that does nothing else.
- [ ] An analysis cannot rename, delete or write into a pre-existing column, and cannot register a file format.
- [ ] Options cross a **1 MiB** hop and results a **4 MiB** hop; both drop silently. Enforce the limit in the browser.
- [ ] `NA` in a nominal output column costs **10 bytes**, not 1 — budget for the missing rate.
- [ ] Splitting a payload across several options buys nothing: the full options object is re-sent every time.

## UI and JavaScript

- [ ] `jus: '3.0'` in `.u.yaml`, or none of the handlers load.
- [ ] `compilerMode: tame`, or the compiler rewrites your hand-built panel on every install.
- [ ] In `tame` mode the compiler still **appends** a control for every new option, including hidden ones.
- [ ] Handler names are `{optionName}_{eventName}`; `view_loaded` fires once per panel type, not per analysis.
- [ ] A `Supplier`/`VariableSupplier` with `populate: manual` **requires** an `updated` handler or jamovi errors.
- [ ] The panel is tested by injecting and clicking it, not by grepping the source.
- [ ] Two-column `cell:` layouts overflow the options panel (about 550 px): the right column is **cut off**, not wrapped. Controls in a `LayoutBox` align on its widest label, so a row is as wide as the widest label plus the widest control (a `ComboBox` is as wide as its longest option). Prefer one column with `Label` groups, and short labels and dropdown texts.
- [ ] A `Variable` option cannot be combined with `&&` / `||` in `visible:` (`(dep && pathTable)` fails with "invalid 'x' type"); keep `visible: (dep)` or set the visibility in `.init()`.

## Build and ship

- [ ] `jmvtools::install()` prints errors on stdout and exits 0 — verify the installed directory.
- [ ] A sandboxed install into `jamovi.app` prints `Module installed successfully` having done nothing.
- [ ] jamovi swaps in a reinstalled module a moment *after* `jmvtools::install()` returns: test the installed copy only once its `DESCRIPTION` `Built:` stamp has changed, or you test the old one (`templates/tools/install.sh` waits for it).
- [ ] `.h.R` / `00jmv.R` / `0000.yaml` are generated; regenerate in CI and fail on a dirty tree.
- [ ] A `Level` option must not carry a `default`, and the generated formal then needs patching to `= NULL`.
- [ ] `00refs.yaml` needs its top-level `refs:` key; without it references vanish and nothing looks wrong.
- [ ] `usesNative` and `minApp` are filled in by `prepare()` when absent — with values you probably don't want.
- [ ] `.gitignore` and `.Rbuildignore` are independent lists; a working directory in one still ships via the other.
- [ ] `NAMESPACE` is hand-maintained if any of it is; roxygen will delete what it did not write.
- [ ] Dependencies resolve from a **frozen CRAN snapshot** — a package dropped from CRAN breaks the *build*, not just behaviour.
- [ ] A `.jmo` is specific to OS + architecture + jamovi series; side-loading across machines usually fails.

## Testing

- [ ] An analysis with a `Data` option and no variable options needs `data = data.frame()` headlessly.
- [ ] `Output` options are not function parameters — enable them by poking private option state.
- [ ] `asProtoBuf()` needs `jmvcore:::initProtoBuf()` first.
- [ ] `Table$asDF` is an active binding, not a method.
- [ ] testthat sources `helper-*.R` globally but shares nothing between test files.
- [ ] Match an external oracle's printing precision before choosing a tolerance.
