# Where the answers are

## The official documentation

<https://dev.jamovi.org> — developer docs (149 pages as of 2026-08).
<https://docs.jamovi.org> — user manual; useful for what a feature *is*, never
for how a module reaches it.

`scripts/mirror-jamovi-docs.sh` pulls a local, greppable copy (~8 MB of HTML,
~360 kB once converted to text). Grep beats clicking, and the local copy pins
what you actually read.

### What each section is good for

| section | worth reading for |
|---|---|
| `tutorial/tuts01xx` | the happy path: first analysis, input checks, rich results, plots, unit testing, module datasets, distributing |
| `tutorial/tuts0200-analysis-lifecycle` | `.init()` vs `.run()` — correct as far as it goes |
| `tutorial/tuts0201-dynamic-tables` | `rows: (option)` and `content: ($key)` data-binding. Use this before writing `.init()` code |
| `tutorial/tuts0201a-advanced-table-techniques` | Group/Array nesting and **table folding** (bracketed column names + `combineBelow`) — genuinely useful and hard to discover elsewhere |
| `tutorial/tuts0202-handling-data` | the dual nature of variables; convert before `na.omit()` |
| `tutorial/tuts0202a-output-variables` | the three-file Output pattern, `setRowNums(rownames(data))` |
| `tutorial/tuts0202b-weighted-data` | `weightsSupport` modes |
| `tutorial/tuts0203-state` | `clearWith`, `isFilled()`, `setState()` |
| `tutorial/tuts03xx` | plot state vs `requiresData`, themes, `setSize2` responsive sizing |
| `api/*` | per-element and per-option-type property tables |
| `ui/*` | control reference; `ui/advanced-customisation` is the JS event contract |
| `misc/updates` | when a feature arrived — the only place `setSize2` (2.7.16) and the Action system (2.7.12) are dated |

### Where the docs are wrong or thin (verified 2026-08-05)

- **`type: Notice` in `.r.yaml` does not compile.** Documented in
  `api/results-definition` and `api/notice`; rejected by the shipped schema. Use
  `jmvcore::Notice$new()` + `results$insert()`. See `yaml-and-compiler.md`.
- **The option-type list is incomplete.** `api/analysis-definition` lists 11
  types; the schema has 19. `String`, `Level`, `NMXList`, `Pairs`, `Pair`,
  `Sort`, `Array`, `Outputs` are real and undocumented.
- **`setRowNums` is presented as always-required.** It is required when mapping
  onto existing rows and must be *omitted* when growing the dataset.
- **The `.init()` guidance stops short.** The docs frame `.run()`-built structure
  as a cosmetic "UI jump"; the real behaviour is that its cells are never
  restored, so the table blanks on every click.
- **Nothing documents the transport ceilings**, the `addRow` cost, or the state
  size warning. All three fail silently.
- `ui/custom-format` is a stub ("Coming soon").
- The docs describe the current series; behaviour differs between series, and
  the pages are not versioned. Pin anything you rely on to a source line.

## The source, which is the actual authority

Clone `https://github.com/jamovi/jamovi` (submodules matter: `jmv`, `i18n`,
`plots`, `readstat`; a plain clone dies at `npm install`). Build from `main` —
series branches go stale.

| question | file |
|---|---|
| how a table restores after a click | `jmvcore/R/table.R` (`fromProtoBuf`, ~:700-780) |
| why `addRow` is slow | `jmvcore/R/table.R:371` |
| `clearWith` default | `jmvcore/R/html.R:40`, and each element class |
| state size warning | `jmvcore/R/results.R:223` (500 000 compressed bytes) |
| how output columns are marshalled | `jmvcore/R/output.R:284-294` |
| `Output` option semantics | `jmvcore/R/options.R:820-838` |
| Notice / NoticeType | `jmvcore/R/notice.R` |
| output columns → spreadsheet, row growth, deletion | `server/jamovi/server/instance.py:316-470` |
| import / Special Import | `server/jamovi/server/instance.py:1071-1200`, `instancemodel.py:495` |
| file-format readers (closed registry) | `server/jamovi/server/formatio/__init__.py` |
| what a module manifest may declare | `server/jamovi/server/modules/modules.py:448-563` |
| where the options panel actually gets its JS | `jamovi-full.yaml` `uijs:` → `client/main/modules.ts:448` → `analyses.ts:86` → `optionspanel.ts:179` |
| the analysis ui js route (lowercasing) — **dead code on 28.x** | `server/jamovi/server/server.py:426`; callers `modules.ts:453` (`_status == 'legacy'`, never assigned) and `optionspanel.ts:186` (`// shouldn't get here`) |
| message size limits | `server/jamovi/server/engine.py:181`, `clientconnection.py:181`, `engine/engine/coms.cpp` |
| the wire format for results and options | `server/jamovi/server/jamovi.proto` |
| the file-type list in the UI | `client/main/backstage.ts:150-166` |
| engines are separate processes | `server/jamovi/server/engine.py:116,155` |

And the compiler that will actually validate your module ships inside jmvtools:

```r
file.path(system.file(package = "jmvtools"), "node_modules/jamovi-compiler/schemas")
```

Read those schemas, not the docs' tables, when a key is rejected.

## Reference implementations

`jmv` (jamovi's own analysis module, a submodule of the main repo) is the best
worked example of everything above at scale — folding, arrays, state, notes,
option layouts. When unsure how something is meant to be done, grep jmv for it
before inventing.
