# Getting data in and out

## Reading the dataset

`self$data` is not a plain data frame. Nominal and ordinal variables arrive as
**factors that also carry underlying numeric values**, and `na.omit()`,
`subset()` and friends strip the attributes that carry them.

```r
data <- self$data
data[[dep]] <- jmvcore::toNumeric(data[[dep]])   # convert FIRST
for (f in facs) data[[f]] <- as.factor(data[[f]])
data <- na.omit(data)                            # clean AFTER
```

`jmvcore::toNumeric` is a no-op on numerics and does the right thing on jamovi's
dual-nature columns, where `as.numeric(as.character(x))` may not.

Ask the user rather than inferring: separate `Factors` and `Covariates` boxes,
not one box you type-sniff. Measure type is a hint users routinely ignore.

In `.init()` jamovi hands you **header-only data** — columns and factor levels,
no values. If the row structure genuinely depends on the values (which variables
have missing data, whether a 0/1 column is binary or continuous), you can read
the real data in `.init()`, but memoise it: `.init()` consults its own
predictions many times per click, and each `self$data` is a full read.

## Writing columns back to the spreadsheet

The `Output` mechanism is the only way an analysis can put data in the
spreadsheet. Three files:

```yaml
# .a.yaml — the user's intent (a checkbox)
- name: residsOV
  type: Output
  title: Residuals

# .r.yaml — the column
- name: residsOV
  type: Output
  varTitle: Residuals
  varDescription: Ordinary residuals
  measureType: continuous
  clearWith: [dep, covs]
```

```r
# .b.R
if (self$options$residsOV && self$results$residsOV$isNotFilled()) {
    self$results$residsOV$setRowNums(rownames(data))
    self$results$residsOV$setValues(residuals(model))
}
```

### What it can do

- **It can grow the dataset.** If the vector is longer than the current row
  count, jamovi extends the dataset:
  `server/jamovi/server/instance.py:424-428` calls `set_row_count(n_values)` and
  refreshes filters. This is what makes importer-style analyses possible at all.
- Multiple columns from one option: set `items:` to a number or an expression
  (`(length(factors))`) in the `.r.yaml`, configure them in one call with
  `set(keys, titles, descriptions, measureTypes)`, then `setValues(v, key = k)`.
- Column types: **integers with levels, or doubles** — that is the whole wire
  format (`jamovi.proto:273-275`). jmvcore converts a character vector to a
  factor for you (`jmvcore/R/output.R:284-294`), so genotype strings and numeric
  dosages both work.

### What it cannot do

- **It cannot rename, delete or write into a column the user already has.**
  Outputs are always created fresh and renamed away from collisions
  (`instance.py:316-372`). The only action an analysis UI can request is
  `createColumn` (`client/analysisui/main.ts:99`).
- A blank sheet has **three real columns** A, B, C (`formatio/blank.py`), not
  rendering artefacts, and a module cannot remove them.
- **An `Output` option cannot default to ticked.** `OptionOutput` takes no
  default and reads `isTRUE(.value$value)` (`jmvcore/R/options.R:820-838`).
  Fine when output is a by-product; wrong for an import analysis, where writing
  the data *is* the point — plan the UX around it and warn when data is loaded
  with the box unticked.

### `setRowNums` — two opposite rules

- **Mapping onto rows that already exist** (residuals, predictions, scores):
  always `setRowNums(rownames(data))`, never `1:nrow(data)`. Filtered and
  NA-dropped frames keep their *original* row names, so sequential integers put
  every value in the wrong row — silently, with no error.
- **Growing the dataset** (an importer producing more rows than the sheet has):
  do **not** call `setRowNums` at all. It maps onto existing rows and throws
  `invalid 'row.names' length` when asked for more than the dataset holds. The
  dense path — values only — is what extends the dataset.

### Scoping and deletion

- Outputs are scoped per analysis (`output_analysis_id`, `instance.py:347`), so
  two analyses own disjoint column sets and accumulate.
- Within one analysis, a key **absent from the current output is deleted**
  (`instance.py:355-358`). That is the mechanism for removing a column, and it
  is sharp: the client places each column at the index the server wrote into the
  message, and the server fills those in *before* deleting
  (`instance.py:444-466`), so anything sent alongside a deletion lands one slot
  too far right — headers and values stop corresponding. **Only a message that
  emits nothing else may delete.** In practice: suspend saving around a reload,
  and to empty a column that a run no longer wants, re-emit its key with no
  values rather than dropping it.
- `rowNums` is shared by every output of one option (`ResultsOutputs`,
  `jamovi.proto:279`) — one row mapping for all the columns it produces.

## The transport ceilings

| hop | carries | limit | set where |
|---|---|---|---|
| browser → server (websocket) | analysis options | 4 MiB | aiohttp default, `clientconnection.py:181` |
| server → engine (nanomsg) | analysis options | **1 MiB** | nanomsg default, `NN_RCVMAXSIZE` never set in `engine/engine/coms.cpp` |
| engine → server (nanomsg) | results, incl. output columns | 4 MiB | `engine.py:181` |
| browser → server (HTTP POST) | file open in server mode | **1 MiB** | aiohttp `client_max_size` default, never raised |

**Every one of them fails silently.** The message is dropped, nothing is logged,
no error reaches the client, R is never told. The results ceiling is worse than
a hang: the engine sends progressive `IN_PROGRESS` results during a run, so when
the final message is dropped the client keeps the last progressive version —
**the tables render and only the data columns are missing**. It looks like it
worked.

Measured costs for output columns:

| missing | bytes/cell | max columns at 10 000 rows |
|---|---|---|
| 0 % | 1.01 | 375 |
| 2 % | 1.19 | 318 |
| 5 % | 1.46 | 259 |
| 10 % | 1.91 | **198** |

A double costs 8.00 B/cell. An `NA` costs **ten** bytes, not one: jmvcore
encodes it as `-2147483648` (`output.R:287`) and a negative int32 varint
sign-extends to 64 bits. Practical cap ≈ **3 million cells** per analysis.

Consequences for design:

- `AnalysisRequest` carries the **full** options object every time
  (`jamovi.proto:50`), so splitting a payload across several options buys
  nothing. Separate *analyses* each get their own budget.
- Enforce the limit in the browser, before sending, and tell the user. Nothing
  downstream will.
- The 4 MiB websocket is the **widest browser → server channel jamovi has** —
  wider than the file-upload endpoint. Base64-in-an-option is not a workaround
  for something better; it is the best channel available.

## Getting files into an analysis

**There is no File option type and no file-picker control.** The option types
are `Data, Variables, Level, Variable, Bool, Action, Integer, Number, String,
List, NMXList, Array, Pairs, Terms, Group, Sort` (plus `Output`, handled
specially by the compiler) — verified from
`jamovi-compiler/schemas/optionschemas.yaml`; `uictrlschemas.yaml` has no file
control.

The working pattern:

1. `.u.yaml` with `jus: '3.0'` and a `jamovi/js/<analysis>.js` handler.
2. The handler injects an `<input type="file">`, reads bytes with `FileReader` /
   `File.slice()`, and writes base64 into a **hidden `String` option**.
3. R decodes, validates and parses. All semantics live in R, where the tests are.

Rules learned the hard way:

- **No path options, ever.** Options are serialised into the `.omv` and re-run
  when it is opened, and an `.omv` is a zip anyone can edit — so a path resolves
  against *the opener's* filesystem, and is an arbitrary-file-read primitive
  wherever the engine does not run as the invoking user. It will not survive a
  security review.
- A web page **cannot open a sibling file the user did not pick**. Anything that
  needs a file trio (`.bed`/`.bim`/`.fam`) must have all three selected together.
- Compress before sending. `CompressionStream('gzip')` in the browser,
  `memDecompress(type = "gzip")` in R, neither needs a package. Worth 1.8× on
  already-packed binary, 13–19× on text.
- `memCompress(type = "gzip")` in R emits **zlib** (`78 xx`), not gzip
  (`1f 8b`). `memDecompress` reads both; `gzcon()` reads only real gzip and
  passes zlib through untouched and silently.
- Prefer `gzcon()` over a `rawConnection()` to inflate untrusted input: it
  streams, so `readBin(con, "raw", n = cap + 1)` caps the output whatever the
  payload contains (0.002 s and 8 MiB peak on a 64 MiB decompression bomb that
  `memDecompress` expanded in full). Note a corrupt stream is not an *error* to
  `gzcon()` — it just stops, and the checksum complaint goes to stderr via
  `REprintf` where no `tryCatch` can see it, so check the length yourself.
- `base64enc::base64decode` **does not validate its input**: invalid characters
  return garbage instead of an error. Check the alphabet first.
- Validate everything in R even though the browser already did. The browser is
  an untrusted client of your own analysis: an `.omv` can be edited.

## A module cannot register a file format

Readers are Python plugins discovered by scanning the server's *own* package
directory at import time (`server/jamovi/server/formatio/__init__.py:22-44`);
an unknown extension raises `Unrecognised file format`. A module definition can
declare only `analyses` and `datasets`
(`server/jamovi/server/modules/modules.py:448-563`) — there is no
importer/reader hook — and the client's file-type list is a literal
(`client/main/backstage.ts:150-166`, shipped verbatim in the bundle). Analyses
also run in a separate `jamovi-engine` process (`engine.py:116,155`), so a
Python-based module cannot patch the registry at runtime either.

**"Special Import"** (File → Special Import) is not an importer framework: it is
a multi-file *merge-append* open. Each selected file is read with the ordinary
`formatio.read`, then merged column-wise by import name with rows appended and a
`source` column naming the origin (`instance.py:1077-1157`,
`instancemodel.py:495-586`). It accepts exactly the formats Open accepts, and a
module cannot add to them.

So: to bring a new format into jamovi, write an **analysis** that reads bytes
from the browser and emits output columns. That is the whole design space.
