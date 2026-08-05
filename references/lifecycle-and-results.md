# The results lifecycle

The single highest-value section. Almost every "my table flickers / renders
empty / is slow on every click" bug is one of the facts below.

## What actually happens on an option click

jamovi does not keep your analysis object alive. On every option change it
**constructs a fresh one**, replays the stored results into it, and then runs
`.init()` and `.run()` again. So:

- `.init()` runs on *every* click, including clicks that change nothing it cares
  about. Anything expensive there drags the whole options panel.
- `.init()` and `.run()` share **one** object per click, so work needed by both
  belongs in a private cache computed once and read twice. Doing it in each is a
  silent doubling.
- Any instance state you set in `.run()` is gone by the next click. It cannot be
  a refill key. Only `setState()` on a results element survives, and only
  subject to that element's `clearWith`.

## Rows and columns must exist by the end of `.init()`

`Table$fromProtoBuf` restores the previous run by iterating over
`private$.rowNames` — the rows that exist *right now* — and looking each one up
by name in the incoming message (`jmvcore/R/table.R:736-760`). The inner loop
does the same for `private$.columns`. A row or column created in `.run()`
therefore has nothing to restore into: the click renders the table **empty**,
`.run()` refills it, and the user sees a blank-then-populate flicker.

```r
.init = function() {
    tbl <- self$results$main
    for (v in self$options$vars)
        tbl$addRow(rowKey = v, values = list(var = v))   # structure here
},
.run = function() {
    tbl <- self$results$main
    for (v in self$options$vars)
        tbl$setRow(rowKey = v, values = list(p = fit(v)$p.value))   # values here
}
```

Two consequences that are easy to get wrong:

- **`tbl$rowCount` is 0 in `.run()` whenever rows were added in `.run()`**, so it
  cannot mean "already filled". It is a fine guard for *writing rows*; it is
  never a guard for *recomputing*.
- If the row set genuinely cannot be known until the data has been analysed
  (haplotype sets, extracted factors), accept the rebuild and cache the
  *computation* instead — see "Caching" below. Do not try to pre-create columns
  for such a table: `.init()` would have to predict a level set that `.run()`
  derives after row filters, and a level that disappears downstream leaves a
  phantom empty column.

### `rows: (option)` in the yaml is the cheapest version of this

Binding `rows:` to an option, with `content: ($key)` on the label column, gets
you correct `.init()`-time structure with no R code at all. Use it whenever the
row set is one-to-one with an option. `.init()` is for structure that is a
*function* of options but not one-to-one (interaction terms, a residuals row).

## `addRow` is quadratic — and you pay it on every click

`jmvcore/R/table.R:371` (still present in 2.7.38):

```r
private$.rowNames <- sapply(private$.rowKeys, toJSON, USE.NAMES = FALSE)
```

Every insertion re-serialises every row name. Measured: **5.4 s for 500 rows**;
**41 s for the 2016 rows** of a 64-SNP LD table, against 1.5 s for the 2016
statistical fits those rows contained. Because rows must be created in
`.init()`, this is the cost of *every checkbox*.

Mitigations, in order of preference:

1. Don't build big tables. Most analyses never reach the regime where this
   matters (10 rows imperceptible, 500 rows 5 s, 2000 rows 40 s).
2. Bind `rows:` in the yaml where you can.
3. Write `.rowKeys` / `.rowCount` and the cells directly, hoisting the
   serialisation out of the loop, and **keep a fallback to `addRow`** so that a
   future jmvcore fix degrades to slow rather than broken.
4. Do **not** monkey-patch `Table`'s R6 method bindings on live objects. It was
   tried, it worked (114 s → 3.4 s), and it was removed: it rebinds locked
   bindings and costs an `R CMD check` NOTE.

A fix has been offered upstream — see `JAMOVI-UPSTREAM-REQUESTS.md` §5.

## `clearWith` — the default is the trap

Every results element defaults to `clearWith: '*'`, i.e. *clear on any option
change* (`jmvcore/R/html.R:40` for Html; the docs state it generally). So:

- An instructions/status `Html` panel with no `clearWith` is wiped on every
  click and flickers back to its placeholder.
- Give each element the **minimal** list of options that actually invalidate it.
  Leaving the "which variables" option *out* of a table's `clearWith` is usually
  right: adding a variable then appends a row instead of clearing the table.
- The mirror image: **an option your render function reads but that is missing
  from an Image's `clearWith` does nothing when toggled.** The render logic looks
  broken and is not.

## Notes (footnotes) need `init = FALSE`

`setNote(key, text)` defaults to `init = TRUE`, which marks the note as an
init-phase placeholder. Protobuf restore then blanks its text and never restores
what the run wrote — and the gated fill that would rewrite it is skipped on a
restored run, so notes render **empty after any click**. Two-part fix:

- every note written during `.run()` uses `init = FALSE`;
- `.init()` re-declares those keys with `init = FALSE` (an empty declaration is
  enough) so no `init = TRUE` placeholder is left behind for a note this run does
  not apply.

## Caching: `setState()`, not instance fields

```r
val <- tbl$state
if (is.null(val)) {
    val <- expensive(...)      # the fit, the EM, the parsed payload
    tbl$setState(val)
}
fill_table_from(val)
```

State lives on the results element and is restored subject to that element's
`clearWith`, which is exactly the invalidation you want. Measured on a real
analysis: first run 34 s, unrelated click **0.17 s with zero refits**, while the
rows themselves were still rebuilt each click.

Rules:

- **Store the minimum.** `jmvcore/R/results.R:223` warns above **500 000
  compressed bytes** — and only warns, to the engine's stdout, where you will not
  see it. What actually kills you is the 4 MiB results ceiling further down the
  pipe, which drops the whole message silently. Check with
  `length(serialize(object, connection = NULL))`.
- Extract, don't stash. A `vcov()` that also carries EM frequency parameters was
  250 kB; the coefficient block alone was 28 kB.
- Never `setState(self$data)`. For plots that genuinely need raw data, declare
  `requiresData: true` on the Image and read `self$data` in the render function.
- Two elements needing the same fit can share it: key the cached object and let
  the second read the first's state.

An R6 field initialised to `new.env()` is evaluated **once at class-definition
time** and shared by every instance — two analyses of the same type in one file
will cross-read each other's cache. Create the environment in `initialize()`.

## Plots

- Sizing belongs in `.init()`. Setting `image$setSize()` only inside the render
  function sizes the image *after* jamovi created the device at the default
  400×300: the first render is upscaled, blurry and clipped, then jumps size on
  the next cycle. Predict the layout in `.init()` and re-assert the same formula
  in the render function for the data-dependent part.
- jamovi ≥ 2.7.16 has `setSize2(widthM, heightM, widthB, heightB)`, splitting
  stretchable (facets) from fixed (axes, margins) pixels so a resize keeps the
  axes crisp. Guard it for older versions:

  ```r
  if ( ! is.null(image[["setSize2"]]))
      image$setSize2(500, 250 * nRows, 100, 100)
  else
      image$setSize(600, 250 * nRows + 100)
  ```
- A render function ends with `print(<ggplot>); TRUE` (or returns the ggplot).
- `requiresData: true` on the Image is the alternative to a fat state.

## Input checks come first

```r
.run = function() {
    if (length(self$options$dep) == 0 || length(self$options$group) == 0)
        return()
    ...
}
```

jamovi runs the analysis the moment it is inserted, before the user has assigned
anything. Without the guard the results panel opens on an R error. Also handle
the responses your analysis cannot use — a response that resolves to "no usable
type" must *say so*, or every downstream table renders as unexplained NAs.
