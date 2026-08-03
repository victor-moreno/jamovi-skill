# Memo — ask for a jamovi-module SKILL in a new project

**The ask:** start a fresh project and have Claude write a reusable SKILL (or a
set of instructions) for building jamovi modules, drawing on everything already
learned here. Do it in a *new* project so the skill is written for jamovi
modules in general, not for SNPstats or snpImport in particular.

**Why:** more modules are planned. Almost every non-obvious behaviour below cost
at least one wrong attempt to find, and several were re-derived more than once
in the same session. The worst example: **table rows must be created in
`.init()`** — the fix went through two wrong theories (`clearWith` lists, then
`deleteRows()` rebuilds) before the real cause was found, *and the answer was
already written down in `SNPstats/R/snpStats.b.R:29-34`.* A skill that front-loads
these facts would have saved all of it.

---

## What the skill should contain

The value is not "how to write an `.a.yaml`" — the jamovi tutorial covers that.
It is the behaviours that are **undocumented, silent, or counter-intuitive**,
each with the file:line that proves it, so a future session can verify rather
than trust.

Suggested shape:

1. **The results lifecycle** — `.init()` vs `.run()`, what survives an option
   click, and the row-creation rule. This is the single highest-value section.
2. **Writing data back** — the `Output` mechanism, what it can and cannot do.
3. **Transport limits** — the three message ceilings and their silent failures.
4. **Getting files in** — there is no file option; the browser-upload pattern.
5. **Testing a module** — including everything that blocks scripted calls.
6. **Building and installing** — desktop, docker, and the install scripts that lie.
7. **A checklist of traps**, each one line, for scanning before writing code.

## Where the evidence already is

Do not re-derive these; they are written up with file:line references:

| file | holds |
|---|---|
| `plink-importer/CLAUDE.md` | the "established facts / do not re-derive" list |
| `plink-importer/bench/README.md` | every measured limit, with the numbers |
| `plink-importer/PLAN.md` | the design reasoning those limits forced |
| `SNPstats/CLAUDE.md` | dependency policy, `.h.R` rules, test structure |
| `SNPstats/R/snpStats.b.R:20-50` | the `.init()` row-creation rule and refresh guards |
| `ondemand-jamovi/CLAUDE.md` | deployment constraints, "no jamovi source is patched" |
| git log of `plink-importer/` | each finding with the symptom that revealed it |

`jamovi-src/` (gitignored, present locally) is the ground truth for all of it.

---

## The traps found so far

Everything below was verified against jamovi 28.1 / jmvcore 2.7.38 during
Phase 0–1 of snpImport, 2026-08-03. Re-verify against the target version before
relying on any of it.

### Results lifecycle — the expensive one

- **Table rows must exist by the end of `.init()`.** jamovi rebuilds the
  analysis object on every option click, and `Table$fromProtoBuf` only restores
  cells into rows that already exist then. Rows added in `.run()` are never
  restored, so every click renders an **empty table and then refills it** — a
  visible blank/flicker. Create rows in `.init()`, `setRow()` values in `.run()`.
  `SNPstats/R/snpStats.b.R:29-34`.
- Because of the above, `tbl$rowCount` is always 0 in `.run()` if rows were added
  in `.run()` — so it cannot be used as a "already filled?" guard.
- **`Table$addRow` is O(n²).** It recomputes
  `.rowNames <- sapply(.rowKeys, toJSON)` on *every* call
  (`jmvcore/R/table.R:371`). Measured **5.4 s for 500 rows**, and since rows
  have to be created in `.init()`, that cost is paid on **every option click**.
  SNPstats hit the same thing at 41 s for 2016 LD-pair rows
  (`SNPstats/R/snpStats.b.R:153-157`, and it has a `docs/jmvcore-addrow-pr/`).
  Workaround: write `.rowKeys` / `.rowCount` and the cells directly and hoist
  the serialisation out of the loop — see `.addRows()` in
  `plink-importer/R/snpImport.b.R`. Keep a fallback to `addRow` so a jmvcore
  change degrades to slow rather than broken.
- Only build rows for a table that is actually shown. A hidden table's rows cost
  exactly as much as a visible one's.
- **`.init()` and `.run()` share one analysis object** (a fresh one per click),
  so expensive work belongs in a private cache computed once and read by both.
  Doing it in each is a silent doubling.
- **`clearWith` defaults to `'*'`** for Html elements (`jmvcore/R/html.R:40`),
  meaning "clear on *any* option change". An instructions panel with no explicit
  `clearWith` is wiped on every click.
- `.init()` runs on every option click, so it must stay cheap. Anything
  expensive there drags the whole options panel.

### Writing data back to the spreadsheet

- An analysis output **can grow the dataset row count** — a column longer than
  the dataset extends it (`instance.py:426-429`). This is what makes data-import
  analyses possible at all.
- Output columns carry **integers (+ levels) or doubles only**
  (`jamovi.proto:273-275`). jmvcore auto-converts a character vector to a factor
  (`jmvcore/R/output.R:284-294`), so genotype strings and dosages both work.
- **Do not call `setRowNums()`** unless mapping onto rows that already exist: it
  throws when asked for more rows than the dataset has. The dense path (no
  rowNums) is what grows the dataset.
- Output columns are **scoped per analysis** (`output_analysis_id`,
  `instance.py:347`), so separate analyses own disjoint column sets and
  accumulate. Within one analysis, columns absent from the current output are
  **deleted** (`instance.py:355-358`).
- An analysis **cannot delete, rename or write into an existing column**. Outputs
  are always created fresh and renamed away from collisions
  (`instance.py:316-372`). The only action an analysis UI can request is
  `createColumn` (`client/analysisui/main.ts:99`).
- A blank sheet has **three real columns** A, B, C (`formatio/blank.py`), not
  rendering artefacts. They cannot be removed by a module.
- **`OptionOutput` cannot default to enabled** — it takes no default and reads
  `isTRUE(.value$value)`. The user must tick the control. Plan the UX around
  that, and warn when data is loaded with the box unticked.

### Transport ceilings — all three fail silently

| hop | carries | limit | set where |
|---|---|---|---|
| browser → server (websocket) | options | 4 MiB | aiohttp default, `clientconnection.py:181` |
| server → engine (nanomsg) | options | **1 MiB** | nanomsg default, never overridden |
| engine → server (nanomsg) | results | 4 MiB | `engine.py:181` |
| browser → server (HTTP POST) | file open | **1 MiB** | aiohttp `client_max_size` default, never raised |

- Exceeding any of them **produces no error**: the message is dropped, nothing
  is logged, the analysis never returns.
- The results ceiling is worse than a hang: the engine also sends *progressive*
  `IN_PROGRESS` results, so **the tables render and only the data columns are
  missing** — the analysis looks like it succeeded.
- Measured costs: **1.19 B/cell** for a genotype factor at 2 % missing, **8.00
  B/cell** for a double. An `NA` costs **ten** bytes, not one, because jmvcore
  encodes it as `-2147483648` (`output.R:287`) and a negative int32 varint
  sign-extends to 64 bits. Practical cap ≈ **3 million cells** per analysis.
- `AnalysisRequest` carries the **full** options object every time
  (`jamovi.proto:50`), so splitting a payload across options buys nothing;
  separate analyses each get their own budget.
- The 4 MiB websocket is the **widest browser → server channel jamovi has** —
  wider than the file-upload endpoint. Base64-in-an-option is not a workaround
  around something better.

### Getting files into an analysis

- **There is no File option type and no file-picker control.** Option types are
  `Data, Variables, Level, Variable, Bool, Action, Integer, Number, String,
  List, NMXList, Array, Pairs, Terms, Group, Sort`.
- The working pattern is injected JS: an `<input type="file">`, `FileReader` /
  `File.slice`, base64 into a hidden `String` option. See
  `SNPstats/jamovi/js/snpPGS.js` and `plink-importer/jamovi/js/snpImport.js`.
- A path option is the wrong answer: it resolves on the opener's machine, not
  the author's, and is an arbitrary-file-read primitive wherever the engine does
  not run as the invoking user.
- A web page **cannot open a sibling file the user did not pick**. Anything that
  needs a file trio must have all three selected together.
- **A module cannot register a file format.** Readers are Python plugins
  discovered by scanning the server's own package directory
  (`formatio/__init__.py:87-89`).

### Testing

- An analysis with a `Data` option and **no variable options** cannot be
  constructed headlessly on a non-empty data frame: jmvcore's `select()`
  (`utils.R:1116-1125`) builds a 0-column frame and assigns the original row
  names to it. Pass `data.frame()`.
- **The `Output` option is not a parameter of the generated function**, so a
  scripted call always leaves it disabled and emits nothing. Enabling it needs
  private state:
  `opts$.__enclos_env__$private$.options[["x"]]$value <- list(value = TRUE, synced = TRUE)`.
- `asProtoBuf()` needs `jmvcore:::initProtoBuf()` first, or it fails on
  `object 'jamovi.coms.Visible' not found`.
- testthat sources `helper-*.R` globally but **does not share definitions
  between test files** — shared fixtures belong in a helper.
- Compare against an outside implementation where one exists, and **match its
  printing precision**: plink's `.frq` carries 4–5 significant figures, so a
  1e-6 tolerance fails on correct numbers.
- Capture golden values from a verified run. Never write them by hand.

### Building and installing

- **`R CMD INSTALL` does not recurse into `R/` subdirectories.** A file at
  `R/vendored/x.R` is silently not installed — no error, just a missing function
  at runtime. Keep everything flat in `R/`.
- `jmvtools::install()` reports compiler and version errors **on stdout and still
  exits 0**. Worse, when the sandbox blocks jamovi.app's SingletonLock it prints
  `Module installed successfully` having installed nothing. Check the module
  directory, not the exit status or the success line.
- The docker install path (`jmc --install` into a running container) works
  reliably and is the better test bed; see `plink-importer/install.sh`.
- In `compilerMode: tame` the compiler **adds a control to `.u.yaml` for every
  option**, including hidden ones, and rewrites the file.
- Modules are R packages, so `src/*.c` compiles and ships — jamovi even relinks
  module `.so` files (`compilerr.js:330`). Rarely needed; vectorising R is
  usually the better answer.

### R6 and jmvcore naming

- **Do not name a private member `.data`.** jmvcore's `Analysis` base class keeps
  the dataset in a private field of that name and assigns to it; an R6 method
  binding blocks that with `cannot change value of locked binding for '.data'`.
  The same risk applies to any base-class private name — check before choosing.
- A `local({ ... })` closure does not survive R6's private-list construction the
  way it does in a plain list; a memoising helper written that way fails with
  `object 'f' not found`. Resolve the function inside the method instead.

### Odds and ends that cost time

- `base64enc::base64decode` **does not validate its input** — invalid characters
  return garbage rather than an error. Check the alphabet yourself.
- `memCompress(type = "gzip")` emits **zlib** (`78 xx`), not gzip (`1f 8b`).
  Only the browser's `CompressionStream('gzip')` emits real gzip.
  `memDecompress` reads both, so accept both magic numbers.
- Parallelism is usually the wrong tool inside an analysis: `mclapply` does not
  work on Windows, and a PSOCK cluster's startup often exceeds the whole
  computation. Vectorise first, and measure before optimising anything.

---

## Also worth capturing in the skill

- **Measure before designing.** The Phase 0 benchmark harness
  (`plink-importer/bench/`) answered three questions in a day that would
  otherwise have been guessed at, and one answer (the 3M-cell results ceiling)
  changed the architecture. A skill should recommend that pattern explicitly.
- **Check the sibling repos before deriving anything.** Two of this session's
  findings were already documented in `SNPstats/`.
- Keep parsers free of jmvcore and of filesystem access so they can be tested
  and audited on their own.
