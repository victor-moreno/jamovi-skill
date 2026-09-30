# The checklist

One line each, grouped by when it bites. Everything here is expanded, with
evidence, in the other reference files. Verified against jamovi 28.1 /
jmvtools 28.3 / jmvcore 2.7.38; the File / `openExternal` / version-gate items
against the jamovi 28.4 source.

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
- [ ] A results item must not be named like a jmvcore `ResultsElement`/`Group` member (`path`, `name`, `title`, `state`, `status`, `items`, `index`, `key`, `parent`, `root`, `options`, `visible`, …). `results$path` then returns your item, and jamovi fails when it serialises the results ("comparison (==) is possible only for atomic and list types"). Headless runs never serialise, so every other test passes.
- [ ] Every option a `renderFun` reads is listed in that Image's `clearWith`.
- [ ] Plot data lives in `image$state` (or `requiresData: true`), never in an R6 field — the image-save path never calls `.run()`.
- [ ] Image state is set only when absent, or every plot re-renders on every click.
- [ ] `ggtheme` is a **list** (theme + two palette scales): `ggtheme + theme(...)` is silently `NULL`, and adding the list replaces the plot's own scales.
- [ ] `geom_text` colour does not follow the theme — take it from `calc_element("text", ...)`.
- [ ] Nor does its **size**: jamovi's theme text is 16 pt (axis text 12.8), so `annotate("text", size = 3.5)` (about 10 pt) comes out at 60 % of the axis text. Size it from the theme: `rel * calc_element("text", theme)$size / ggplot2::.pt`.
- [ ] A 550 px plot has no room for two legends side by side at 16 pt: the top legend overflows and is cut at both edges. Stack them (`legend.box = "vertical"`) or shorten the labels.
- [ ] Run-phase notes are set with `init = FALSE`, and stale placeholder keys are re-declared in `.init()`.
- [ ] Cached state stays well under **500 000 compressed bytes** (`jmvcore/R/results.R:223`).
- [ ] `type: Notice` in `.r.yaml` **does not compile**; build `jmvcore::Notice$new()` and `results$insert()`.
- [ ] `type: Notification` compiles and then dies at runtime with "attempt to apply non-function".
- [ ] A dynamically inserted element has no `self$results$<name>` binding — reach it with `$get("name")`.
- [ ] Status messages and panel JS never hardcode a colour. jamovi (to 28.4) has no dark theme (its `theme` setting only styles plots), but a hex grey assumes a white page, and OS high-contrast mode overrides colours anyway. Use platform elements (Notice, native `disabled`) or translucent greys, `rgba(128, 128, 128, a)`.

## Data in and out

- [ ] `weightsSupport` is declared, not inherited: the fallback is `none` with an `Output` option and `auto` without, and `auto` replicates rows so `nrow(self$data)` is the sum of the weights.
- [ ] Convert types (`jmvcore::toNumeric`, `as.factor`) **before** `na.omit()`/`subset()` — they strip jamovi's attributes.
- [ ] An **ordinal** variable arrives as an **ordered factor** (`engine/readdf.cpp:263`), and `as.factor()` keeps it ordered, so `coxph`/`glm`/`lm` code it with polynomial contrasts (`.L`, `.Q`) instead of level-versus-reference: use `factor(x, ordered = FALSE)` before modelling. Headless tests with plain factors never see it.
- [ ] Output columns: `setRowNums(rownames(data))`, never `1:nrow(data)` — silently wrong under any filter.
- [ ] Output columns that must **grow** the dataset: do not call `setRowNums` at all.
- [ ] Output columns carry integers (+levels) or doubles only; character vectors are auto-factored.
- [ ] An `Output` option cannot default to ticked — design the UX (and a warning) around that.
- [ ] Within one analysis, an output key you stop emitting **deletes** its column; deletion is only safe in a message that does nothing else.
- [ ] An analysis cannot rename, delete or write into a pre-existing column, and cannot register a file format.
- [ ] Files come in through a `File` option (jamovi ≥ 28.3), never a path `String`. Its `.u.yaml` control is `File` in 28.4 but was `FileSelector` in 28.3: a `.jmo` built for one breaks the panel on the other, so `minApp` must match the jmvtools you build with.
- [ ] A `File` option gives the panel JS only `{id, filename}`, never the bytes. Client-side slicing still needs the browse-button pattern.
- [ ] A `File` option copies the **whole** file into the session and into every saved `.omv`, capped at 100 MB per session on cloud. It is not for multi-GB inputs.
- [ ] Don't require `jmvcore (>= 28.3)` for `OptionFile`: jamovi 28.3.0.0's bundled jmvcore has it but reports 2.7.38.
- [ ] `action: openExternal` (≥ 28.4) needs a returned `filename`. The desktop opens only allowlisted extensions (not `.gz`), and the file is served once.
- [ ] Guard an `Action`'s `perform()` so it runs once per click; SNPstats saw the option stay TRUE across later runs.
- [ ] Options cross a **1 MiB** hop and results a **4 MiB** hop; both drop silently. Enforce the limit in the browser.
- [ ] `NA` in a nominal output column costs **10 bytes**, not 1 — budget for the missing rate.
- [ ] Splitting a payload across several options buys nothing: the full options object is re-sent every time.
- [ ] Data Library entries (`datasets:` in `0000.yaml`) have a fixed height: a description over about 150 characters (two lines) runs over the next entry.

## UI and JavaScript

- [ ] `jus: '3.0'` in `.u.yaml`, or none of the handlers load.
- [ ] `compilerMode: tame`, or the compiler rewrites your hand-built panel on every install.
- [ ] In `tame` mode the compiler still **appends** a control for every new option, including hidden ones.
- [ ] Handler names are `{optionName}_{eventName}`; `view_loaded` fires once per panel type, not per analysis.
- [ ] A `Supplier`/`VariableSupplier` with `populate: manual` **requires** an `updated` handler or jamovi errors.
- [ ] The panel is tested by injecting and clicking it, not by grepping the source.
- [ ] Two-column `cell:` layouts overflow the options panel (about 550 px): the right column is **cut off**, not wrapped. Controls in a `LayoutBox` align on its widest label, so a row is as wide as the widest label plus the widest control (a `ComboBox` is as wide as its longest option). Prefer one column with `Label` groups, and short labels and dropdown texts.
- [ ] A `LevelSelector` label is never translated: `levelselector.ts:64-72` renders it without `translate()` (unlike `gridcombobox.ts`), whatever the module's catalog says.
- [ ] The plain arrow of a Terms box with `transferAction: interactions` adds the selected variables **and** their product; ignore one-variable terms in R and point users to the arrow's menu → *Interaction* (`screenshots.md`).
- [ ] A `Variable` option cannot be combined with `&&` / `||` in `visible:` (`(dep && pathTable)` fails with "invalid 'x' type"); keep `visible: (dep)` or set the visibility in `.init()`.

## Build and ship

- [ ] `jmvtools::install()` prints errors on stdout and exits 0 — verify the installed directory.
- [ ] A sandboxed install into `jamovi.app` prints `Module installed successfully` having done nothing.
- [ ] jamovi swaps in a reinstalled module a moment *after* `jmvtools::install()` returns: test the installed copy only once its `DESCRIPTION` `Built:` stamp has changed, or you test the old one (`templates/tools/install.sh` waits for it).
- [ ] `.h.R` / `00jmv.R` / `0000.yaml` are generated; regenerate in CI and fail on a dirty tree.
- [ ] A `Level` option must not carry a `default`, and the generated formal then needs patching to `= NULL`.
- [ ] `00refs.yaml` needs its top-level `refs:` key; without it references vanish and nothing looks wrong.
- [ ] `usesNative` and `minApp` are filled in by `prepare()` when absent — with values you probably don't want.
- [ ] jmc/jmvtools 28.4 refuses any jamovi 28.0–28.3 (`installer.js:104`), even for `--prepare`/`prepare()`. It still accepts 2.x (solid). Update the app before, or together with, jmvtools.
- [ ] `.gitignore` and `.Rbuildignore` are independent lists; a working directory in one still ships via the other.
- [ ] `NAMESPACE` is hand-maintained if any of it is; roxygen will delete what it did not write.
- [ ] Dependencies resolve from a **frozen CRAN snapshot** — a package dropped from CRAN breaks the *build*, not just behaviour.
- [ ] A `.jmo` is specific to OS + architecture + jamovi series; side-loading across machines usually fails.
- [ ] Docker (jamovi ≥ 28.4): install with the host's `jmc --install <module> --home docker:<container>` (the template's `install.sh docker`), not `jmc` inside the image. It needs nothing in the image, but the Docker VM must see the module repo read-write.
- [ ] Modules and settings (language) live in the container's `/root/.jamovi`. Without a volume there (`scripts/docker-setup.sh`), `down`/`up` loses them.
- [ ] Upstream's `docker-compose.yaml` still tags the 28.4 image as `jamovi/jamovi:28.1`. Override the tag, or `build` mislabels it and `up` runs an old image.
- [ ] Never override an existing `DOCKER_CONFIG`: it hides buildx, and the legacy builder then fails on `$BUILDPLATFORM`.

## Testing

- [ ] An analysis with a `Data` option and no variable options needs `data = data.frame()` headlessly.
- [ ] `Output` options are not function parameters — enable them by poking private option state.
- [ ] `asProtoBuf()` needs `jmvcore:::initProtoBuf()` first.
- [ ] Serialise each analysis as jamovi does in the tests: build it with `<name>Class$new(options = <name>Options$new(...), data = df, datasetId = "d", analysisId = "1", revision = 1)`, call `init()` and `run()`, then `RProtoBuf::serialize(an$asProtoBuf(final = FALSE, includeState = TRUE), NULL)`. Calling `asProtoBuf()` on the results of a headless wrapper fails for unrelated reasons (no analysis context).
- [ ] `Table$asDF` is an active binding, not a method.
- [ ] jamovi cloud autosaves an edited `.omv` over the file it was opened from when the browser disconnects: a scripted run (screenshots, UI tests) must open a fresh copy each time (`screenshots.md`).
- [ ] testthat sources `helper-*.R` globally but shares nothing between test files.
- [ ] Match an external oracle's printing precision before choosing a tolerance.
