# Testing a jamovi module

A module is an ordinary R package, so testthat works — but a jamovi *analysis*
is not an ordinary function, and several things block a scripted call.

## Calling the analysis headlessly

`jmvtools::prepare()` generates a public function per analysis (`ttest(...)`)
that constructs the options, runs the analysis and returns the results object.
That is what you test.

```r
results <- MyModule::ttest(data = df, dep = "len", group = "supp")
tbl <- results$ttest$asDF        # active binding, not a method, in jmvcore >= 2
expect_equal(tbl$p[1], 0.06, tolerance = 1e-3)
```

Gotchas:

- **`asDF` is an active binding.** `results$tbl$asDF()` fails.
- **A `Data` option with no variable options needs `data = data.frame()`.**
  jmvcore's `select()` (`jmvcore/R/utils.R:1116-1125`) builds a 0-column frame
  and assigns the original row names to it, which errors on any non-empty
  input. Applies to every importer-style analysis.
- **Tidy-eval wrappers deparse their argument.** The generated function resolves
  `snps`/`response` with `jmvcore::resolveQuo`, so passing a *variable* gives you
  the variable's name, not its value. Use `do.call(f, list(...))` to inline
  values in a test helper.
- **`asProtoBuf()` needs `jmvcore:::initProtoBuf()` first**, or it dies on
  `object 'jamovi.coms.Visible' not found`.

## Enabling an `Output` option from R

`Output` options are **not parameters of the generated function**, so a scripted
call always leaves them off and the analysis emits no columns. Reach into the
private option state:

```r
enable_output <- function(opts, name) {
    p <- opts$.__enclos_env__$private
    p$.options[[name]]$value <- list(value = TRUE, synced = TRUE)
    p$.env[[name]] <- TRUE
    opts
}
```

Construct the `<analysis>Options` object, enable, then build the analysis class
around it. This is the only way to test the spreadsheet-writing half at all.

## Two layers that catch different things

**Oracle tests** recompute every result a second, independent way — plain
`glm`/`lm`, a brute-force enumeration, a numerical maximisation instead of an
EM, or an outside tool's output. They catch regressions in your own logic, and a
*correctness* oracle (assert that the estimate is the argmax) is stronger than an
*agreement* oracle (assert it matches another implementation), because it cannot
drift with someone else's release.

**Golden tests** pin numbers captured from a verified run. They catch the R or
package upgrade that silently shifts results while the module is unchanged. When
one fails: confirm the oracle layer still passes, *then* update the golden.
Never write a golden value by hand.

Two practical notes:

- **Match the oracle's printing precision.** An external tool reporting 4–5
  significant figures will fail a `1e-6` tolerance on numbers that are correct.
- If a result depends on the RNG (EM algorithms often consume it), wrap the fit
  so it sets a fixed seed and restores the caller's RNG state on exit —
  otherwise the analysis is not reproducible run to run and no golden value is
  stable.

## Structure

- testthat sources `helper-*.R` globally but **shares nothing between test
  files** — every shared fixture or oracle belongs in a helper.
- Keep pure compute (parsers, statistics) in functions with no jmvcore, no R6,
  no `self`, and no file access. They are then testable directly, and a
  `grep -rn "file(\|readLines\|system\|eval(" R/` that finds nothing outside the
  generated header is a cheap standing assertion.
- Capture fixtures from the real tool that produces the format, and commit only
  the smallest tier; generate the larger ones from a script.

## What only a running jamovi will tell you

Unit tests cannot see the restore cycle, which is where the expensive bugs live.
Add a **refresh test**: run the analysis, serialise and restore it, simulate an
unrelated option change, and assert that the tables come back with identical
rows, columns and cells **and** that the expensive function was called zero
extra times (count calls with a mocked binding). That is the test that pins the
`.init()` row rule, the `clearWith` lists and the state caching all at once.

Then still click it in a real jamovi — desktop *and* a Linux container, because
the case-sensitivity and cloud-transport failures are invisible on macOS.

## Keep the generated files honest

`R/*.h.R`, `R/00jmv.R` and `jamovi/0000.yaml` are committed and generated. Have
the test script regenerate them and **fail if the tree is left dirty**; a stale
`.h.R` has shipped a table note the `.r.yaml` had already changed.
