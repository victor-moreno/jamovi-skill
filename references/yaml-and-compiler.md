# The yaml files and the compiler

The schemas in `jamovi-compiler/schemas/` are the authority, not the docs. They
ship inside jmvtools, so you can always read the ones that will actually
validate your module:

```
$(Rscript -e 'cat(system.file("", package="jmvtools"))')/node_modules/jamovi-compiler/schemas/
├── analysisschema.yaml      # .a.yaml: top-level keys + the option type enum
├── optionschemas.yaml       # per-option-type properties
├── resultsschema.yaml       # .r.yaml: the element type enum
├── resultelementschemas.yaml# per-element properties
├── uischema.yaml            # .u.yaml top level
└── uictrlschemas.yaml       # every UI control and its properties
```

Everything below is read from those files at jamovi-compiler 0.3.5 (jmvtools
28.3) and, where noted, confirmed by compiling a throwaway module.

## `.a.yaml` — options

Required top-level keys: `name`, `title`, `jas`, `version`, `menuGroup`,
`options`. `version` must match `^[0-9]+\.[0-9]+\.[0-9]+$` and `jas` must be
quoted so yaml does not read it as a number.

Documented and useful: `menuSubgroup`, `menuTitle`, `menuSubtitle`, `category`
(`analyses` | `plots`), `weightsSupport` (`auto` | `integerOnly` | `full` |
`none`), `description`.

Present in the schema and **not** in the docs: `rename` (for renaming an
analysis without orphaning saved files), `addonFor` (`pkg::analysis` — attaches
this analysis's results to another module's analysis, and hides it from the
menu), `arbitraryCode`, `completeWhenFilled`, `export`, `pause`, `formula`.

### Option types — the authoritative list

`analysisschema.yaml` enum: **Data, Level, Variable, Variables, Terms, Integer,
Number, String, Bool, List, NMXList, Array, Pairs, Sort, Output, Outputs, Pair,
Group, Action**.

The docs list eleven of these. `String`, `NMXList`, `Level`, `Pairs`, `Pair`,
`Sort`, `Array`, `Outputs` are real and undocumented. There is **no File type**
— see `data-io.md` for how files actually get in.

`Output` and `Outputs` are special-cased by the compiler (`compiler.js:220`):
they take no value and no properties beyond name/title, which is why an `Output`
option cannot have a default.

### `Level` options must not carry a `default`

A `Level` option (`variable: (responseCol)`, rendered as a `LevelSelector`)
is rejected by the compiler if it has a `default`:
`... is not allowed to have the additional property "default"`. But with no
default, `jmvtools::prepare` emits a **bare formal** in the generated public
function — `caseLevel,` — so the documented R call throws
`argument "caseLevel" is missing`. The same happens to any option you leave
without `default: ~`.

Fix: give every non-`Level` option an explicit `default: ~` where NULL is
meaningful, and for `Level` options patch the generated `.h.R` formal to
`= NULL` from a **script** that runs after every `prepare`/`install` — never by
hand, or the next build wipes it silently.

## `.r.yaml` — results

Required: `name`, `title`, `jrs`, `items`. `items` must be a non-empty array.

### The element type enum, and the `Notice` trap

`resultsschema.yaml` enum: **Table, Group, Array, Image, Preformatted, Html,
State, Property, Output, Notification, Action**.

dev.jamovi.org documents `type: Notice` as a results element. **It does not
compile.** Verified by building a minimal module:

```
Unable to compile 'nt.r.yaml':
    results.items[0].type is not one of enum values:
    Table,Group,Array,Image,Preformatted,Html,State,Property,Output,Notification,Action
```

`type: Notification` *is* in the enum, compiles, and then dies at runtime —
`sourcifyResults` emits it as a bare `list(name=…, type="Notification")` rather
than an element object, so constructing the results throws **"attempt to apply
non-function"**. (`compiler.js` does know about `Notice` internally; only the
schema was never updated. A one-line upstream fix.)

The route that works is dynamic construction:

```r
notice <- jmvcore::Notice$new(options = self$options, name = "violation",
                              type = jmvcore::NoticeType$STRONG_WARNING)
notice$setContent("Assumption of normality was violated.")
self$results$insert(1, notice)
```

`NoticeType` is `INFO` / `WARNING` / `STRONG_WARNING` / `ERROR`
(`jmvcore/R/notice.R`). Note a dynamically inserted element gets **no**
`self$results$<name>` active binding — those are generated from the yaml — so
reach it with `self$results$get("violation")`.

If you cannot use a Notice, use `type: Html` and let the platform pick the
colour: **never hardcode one**, it is unreadable in the dark theme.

`type: State` has a broken constructor upstream; element-attached state
(`element$setState()`) is the mechanism you actually want, and is unrelated.

### Element properties worth knowing

`clearWith` (defaults to `*` — see `lifecycle-and-results.md`), `visible` (can
be data-bound: `visible: (showThing)`), `refs`, `rows: (option)`,
`content: ($key)`, `combineBelow`, bracketed column names for table folding, and
on Images: `renderFun`, `width`/`height`, `requiresData: true`.

## `.u.yaml` — the options panel

`jus: '3.0'` is required for JavaScript handlers to load at all. `compilerMode`
is `aggressive` by default, which **regenerates and overwrites the file on every
build**; set `compilerMode: tame` the moment you hand-edit it.

Even in `tame` mode the compiler **appends a control for every option it does
not find**, including `hidden: true` ones, and rewrites the file to do it. So a
hidden String option used as a payload carrier will grow a stray TextBox in your
panel unless you place it yourself (inside a hidden container).

## `0000.yaml` and `00refs.yaml`

`0000.yaml` is **generated** by `prepare()` from the `.a.yaml` files plus the
hand-written module metadata. Two fields are filled in when absent
(`jamovi-compiler/index.js:296-300`) with values you may not want:

- `usesNative: true` — wrong if the module has no `src/`;
- `minApp: 1.0.8` — wrong if you depend on behaviour introduced later.

Set both explicitly. Any comment you write next to them does not survive a
`prepare()`, so the reasoning belongs in the project's notes.

`datasets:` in `0000.yaml` registers bundled example data (`.omv` or `.csv` in
`data/`) into jamovi's Data Library — the one supported way for a module to ship
data.

`00refs.yaml` **needs a top-level `refs:` key** and fails silently without one:
the compiler reads `yaml.load(content).refs` (`index.js:326`), entries written at
the top level are read as no references at all, and everything still looks fine
— the `.jmo` carries `refs.yaml` verbatim and the `.r.yaml` names still compile
into the header. The tell is `R/00jmv.R`: if `prepare()` does not write it, the
definitions never reached R.

## Generated files

`R/<analysis>.h.R`, `R/00jmv.R`, `jamovi/0000.yaml` and `build/js/*.src.js` are
generated. They are usually committed (jamovi's library builds from source), so
they **go stale**: a shipped `.h.R` once carried a table note the `.r.yaml` had
already changed. Regenerate them in the test script and fail if that leaves the
tree dirty.

Never hand-edit a `.h.R`. If a generated artefact is wrong (the `Level` default
above), fix it with a patch script invoked by both the install and the test
entry points.
