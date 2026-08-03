# What to ask the jamovi developers for

Ceilings that limit how much data a jamovi module can move, each with where it
is set, what it costs, and the change that would lift it. Everything here was
measured against **jamovi 28.1 / jmvcore 2.7.38** while building `snpImport`
(a PLINK genotype importer); re-check line numbers against the target version
before filing.

Ordered by value for effort. **The first item is worth more than all the others
put together** — not because it raises a limit, but because it makes the limits
visible.

---

## 1. Fail loudly when a message is too big  ★ highest value, low effort

**Today every one of the size limits below fails silently.** The message is
dropped, nothing is logged, no error reaches the client, and the analysis simply
never returns. There is no way for a module author to detect it from R, because
R is never told.

The results ceiling is worse than a hang. The engine sends progressive
`IN_PROGRESS` results during a run, so when the final `COMPLETE` message is
dropped **the client keeps the tables from the last progressive send** — the
analysis renders its output tables and only the data columns are missing. It
looks like it worked.

That cost days of debugging on our side, and any module hitting it will look
broken to its users for reasons its author cannot see.

**Ask:** on an oversize message, log it and surface an analysis-level error
(`Results too large to transfer: N MB, limit M MB`). Even with no limit raised,
this turns an unexplainable hang into a one-line diagnosis.

Relevant places: `server/jamovi/server/clientconnection.py:196-197` breaks out of
the read loop on `WSMsgType.ERROR` without reporting; the nanomsg paths drop
oversize frames inside the library.

---

## 2. `client_max_size` on the HTTP app — a one-line bug, affects every cloud user

**jamovi in server mode cannot open any file larger than 1 MiB from a browser.**

`server.py:751` creates the app with no `client_max_size`, so aiohttp's 1 MiB
default applies to the `/open` multipart upload (`server.py:230-259`). Measured
against a stock `jamovi/jamovi:28.1` container:

```
test_0.5MB.csv    0.52 MB -> HTTP 200   works
test_2.0MB.csv    2.12 MB -> HTTP 413   Maximum request body size 1048576 exceeded
test_10.0MB.csv  10.72 MB -> HTTP 413
```

A plain 2 MB CSV is rejected. This is not a module concern at all — it is
ordinary jamovi use in the browser.

**Ask:**

```python
main_app = web.Application(client_max_size=1024 ** 3)   # server.py:751
```

Note the `separate_by == 'path'` mode also wraps everything in `root_app`
(`server.py:782`), which may need the same argument.

---

## 3. Raise, or make configurable, the three message ceilings

| hop | carries | limit | set where |
|---|---|---|---|
| browser → server (websocket) | analysis options | 4 MiB | aiohttp default, `clientconnection.py:181` |
| server → engine (nanomsg) | analysis options | **1 MiB** | nanomsg default, **never set** |
| engine → server (nanomsg) | results, incl. output columns | 4 MiB | `engine.py:181` |

Two of these are unintentional — they are library defaults nobody chose.

**3a. Server → engine is the tightest, and it is accidental.**
`engine/engine/coms.cpp:56-70` sets only `NN_SNDTIMEO` and `NN_RCVTIMEO`;
`NN_RCVMAXSIZE` is never set, so nanomsg's 1 MiB default applies. Confirmed in
the container:

```
engine-side default RCVMAXSIZE: 1048576 bytes = 1.0 MiB
```

The server side deliberately raised its own to 4 MiB (`engine.py:181`, with the
comment *"max size of nanomsg messages ... default was 1Mb under macOS"*), so
the omission on the engine side looks like an oversight rather than a decision.

```cpp
int maxsize = 64 * 1024 * 1024;
nn_setsockopt(_socket, NN_SOL_SOCKET, NN_RCVMAXSIZE, &maxsize, sizeof(maxsize));
```

**3b. The websocket ceiling is also just a default.**

```python
max_msg_size = int(conf.get('max_message_size', 4 * 1024 * 1024))
ws = web.WebSocketResponse(heartbeat=heartbeat, max_msg_size=max_msg_size)
```

`conf` already maps any `JAMOVI_*` environment variable to a lowercase key
(`utils/conf.py:72-76`), so a `conf.get` here makes it tunable per deployment
with no rebuild — matching how `timeout_no_websocket_ping_interval` is handled
two lines above.

**3c. The results ceiling is what caps analysis output.** Same treatment: read
it from `conf` rather than hard-coding 4 MiB.

**Why it matters concretely.** Output columns are the only way an analysis can
put data into the spreadsheet. At 4 MiB the ceiling is about **3 million cells**,
so on a 10 000-sample cohort an analysis can emit roughly **300 columns**.
Measured: 300 × 10 000 works, 400 × 10 000 does not.

---

## 4. Stop `NA` costing ten bytes in output columns

`ResultsOutput` sends nominal columns as `repeated int32 i` (`jamovi.proto:274`),
and jmvcore encodes a missing value as `-2147483648` (`jmvcore/R/output.R:287`).
proto3 packs `int32`, but a **negative** `int32` varint is sign-extended to 64
bits, so every missing value costs **10 bytes where a genotype costs 1**.

Measured at 10 000 rows × 100 columns, varying only the missing rate:

| missing | bytes/cell | max columns @ 4 MiB |
|---|---|---|
| 0 % | 1.006 | 375 |
| 2 % | 1.185 | 318 |
| 5 % | 1.458 | 259 |
| 10 % | 1.906 | **198** |

**10 % missing costs 47 % of the transferable capacity** — and missing data is
the normal case in the fields jamovi serves.

**Ask,** in rough order of preference:

1. Use `sint32` (zigzag) for the values field, where −2147483648 costs 5 bytes
   rather than 10. Wire-format change, needs a protocol version bump.
2. Or send missingness as a separate packed bitmask and keep the values field
   non-negative — cheapest on the wire, biggest change.
3. Or reserve a small positive sentinel (e.g. `0`, with levels 1-based as they
   already are) so a missing value costs one byte.

Option 3 may be achievable without a protocol change at all.

---

## 5. `Table$addRow` is quadratic

`jmvcore/R/table.R:371` recomputes every row name on every insertion:

```r
private$.rowNames <- sapply(private$.rowKeys, toJSON, USE.NAMES=FALSE)
```

So building *n* rows costs O(n²) JSON serialisations. Measured **5.4 s for 500
rows**; SNPstats measured **41 s** for the 2016 rows of a 64-SNP LD table.

This is not a size limit but it is a hard scalability limit on results, and it
bites twice over: rows must be created in `.init()` for
`Table$fromProtoBuf` to restore their cells, and `.init()` runs on **every
option click** — so the quadratic cost is paid on every checkbox.

**Ask:** hoist the serialisation out of the loop, or maintain `.rowNames`
incrementally. A patch already exists on our side —
`SNPstats/docs/jmvcore-addrow-pr/`.

---

## 6. Smaller asks

**Send only changed options.** `AnalysisRequest` carries the *full* options
object on every request (`jamovi.proto:50`) alongside a `changed` list. Any
module using the base64-in-a-hidden-option pattern (the only way to get a file
into an analysis) therefore re-sends the entire payload on every click, and
cannot split a large payload across several options to get under the ceiling.

**Let `Output` options default to enabled.** `OptionOutput` takes no default and
reads `isTRUE(private$.value$value)` (`jmvcore/R/options.R:820-838`), so the user
must always tick the box. Sensible when output is a by-product; wrong for an
import analysis, where writing the data *is* the purpose — a user who loads a
file and does not notice the checkbox sees nothing happen.

**A `deleteColumn` action for analyses.** `requestAction` supports only
`'createColumn'` (`client/analysisui/main.ts:99`). A blank sheet carries three
real placeholder columns A, B, C (`formatio/blank.py`) that an import cannot
remove or reuse, because outputs are always created fresh and renamed away from
collisions (`instance.py:316-372`). The plumbing is half there already.

---

## How to frame the request

Items 1 and 2 are defect reports and can be filed as such — item 2 in particular
is a one-line change affecting anyone running jamovi in the browser, with no
module involved. Items 3–5 are enhancements with concrete diffs. Item 6 is a
wish list.

Offering the measurements is likely to help: every number here is reproducible
against a stock `jamovi/jamovi:28.1` container, and the harness that produced
them is `plink-importer/bench/` in this workspace.
