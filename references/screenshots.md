# Screenshots and walkthrough videos from jamovi in Docker

A tutorial or README for a module is better with pictures of the real panel:
where the options are, what the reader should tick, what jamovi then shows.
Taking them by hand goes stale with every UI change. Capture them instead, with
a script, from jamovi cloud in a Docker container: rerun it and every figure is
current. The same run is also the cheapest UI check there is, because it clicks
the panel the way a user does (it found the translation bug below).

**Verified on 2026-09-27** capturing the jamovi-prognosis tutorial:
`jamovi/jamovi:28.1` (R 4.6.0, arm64 under OrbStack), Playwright 1.62 with
headless Chromium, in English and in Spanish, from a sandboxed agent session.

## The tool

**jamovi-automation** (a separate repository, checked out beside the module)
holds the Playwright helpers: `jamovi_capture.py` for screenshots,
`jamovi_labels.py` for other languages, `jamovi_record.py` for captioned videos,
and `jamovi_container.sh` to start a container. Its README has the helper list
and the selector notes; this page is the workflow for a module.

    cd ../jamovi-automation
    uv sync
    PLAYWRIGHT_BROWSERS_PATH="$PWD/.browsers" uv run playwright install chromium

- Headless Chromium runs in a sandboxed session (Firefox did not start there:
  `sandbox_init() failed`).
- In a sandbox that cannot write `~/.cache/uv`, set `UV_CACHE_DIR` to a folder
  in the project.
- Do not copy `.browsers/` from another machine or architecture: an x64 copy
  under an arm64 Python fails ("Executable doesn't exist ... mac-arm64", and an
  ffmpeg `EACCES`), and `playwright install` skips it because the copy's
  `INSTALLATION_COMPLETE` marker says done. Delete the folders and install again.

## A capture container for the module

Use a container of your own, on its own ports, rather than one another project
uses: recreating a container to change its language drops the modules installed
into it, and its server language is shared by every client.

    export JAMOVI_CONTAINER=jamovi-capture JAMOVI_PORT=41437
    JAMOVI_DOCS_DIR=.tmp/jamovi-capture/docs bash ../jamovi-automation/jamovi_container.sh en
    bash tools/install.sh docker jamovi-capture      # jmc --install + tools/smoke.R

- The server opens three consecutive ports from the one it is given
  (`jamovi/server/__main__.py:110`): the page, the options iframe, the results
  iframes. `JAMOVI_HOST_A/B/C` must name the published ports; the script
  publishes the same numbers inside and out.
- `JAMOVI_LANG` fixes the server language at startup: every `JAMOVI_*` variable
  becomes a conf key (`utils/conf.py:72-76`), `session.py:105-107` applies `lang`,
  and `session.py:140-142` then ignores what clients ask for. Without it, the
  first request that sets a language wins for the life of the process. A saved
  `selectedLanguage` setting still comes first (`session.py:100`); a fresh
  container has none.
- The stock image includes `jmc`, so the template's `install.sh docker` works in
  a fresh container, and `jmc --install` compiles `jamovi/i18n/*.po` itself: the
  installed module has its translations (measured: `R/<module>/i18n/es.json`).
- A module installed with `jmc --install` lives in `/usr/lib/jamovi/modules`,
  inside the container: recreate the container (another language) and install it
  again. Library and sideloaded modules live in the mounted modules folder.

## The recipe

Keep the capture script with the figures it writes, e.g.
`tutorial/screenshots/capture.py` beside its PNGs, and run it from the module
repository with the tool's environment:

    PLAYWRIGHT_BROWSERS_PATH=../jamovi-automation/.browsers \
        uv run --project ../jamovi-automation python tutorial/screenshots/capture.py

One session can produce every figure: open the data, run each analysis, save a
PNG after each step the text describes. The prognosis recipe (about 100 lines)
captures the Variables tab, a Kaplan-Meier window, the Cox options panel, an
interaction term and a plot section.

- Name labels in **English**, as in the `.a.yaml`/`.u.yaml`. The same recipe
  then captures another language: start the container in it and set
  `JAMOVI_CAPTURE_LANG`; labels are translated from the container's own catalogs
  (jamovi's and every installed module's `R/<module>/i18n/<lang>.json`).
- A module's menu entry shows its `menuSubtitle` under the title, so its
  accessible name is both: select it with `exact=False`.
- **Copy the data in fresh at the start of every run** (`put_file()`). When a
  browser disconnects, jamovi autosaves an edited data set in jamovi format over
  the file it was opened from (`session.py`: `instance.autosave()` before an
  instance without connections is closed; `instance.py`: `needs_autosave()`).
  Measured: the `.omv` grew from 2.9 KB to 49.5 KB with seven analyses, and the
  next run opened them all. Never mount a folder of files you care about as the
  container's `/root/Documents`. CSV files are not written back.
- A long options panel scrolls inside its iframe. Enlarge the window before
  opening the analysis and crop one section at a time.
- A section declared `collapsed: false` starts open, and clicking its header
  closes it; the header's `aria-expanded` says which.
- Crop the results above jamovi's "References" footer, a content-independent
  marker of where an analysis ends.

## Interaction terms need three workarounds

- The plain transfer arrow of a Terms box (`transferAction: interactions`) adds
  the selected variables **and** their product: two selected, three terms. The
  arrow with a menu (`.jmv-variable-interaction-transfer`) → *Interaction* adds
  the product alone. So the R side must ignore one-variable terms
  (`Filter(function(t) length(t) > 1, options$interactions)`), and the tutorial
  should tell the reader to use the menu.
- The menu's *Interaction* is enabled only with two or more variables selected
  (`gridtargetcontrol.ts`, `checkEnableState`), and its toolbar group carries
  `aria-disabled="true"` even then, so Playwright refuses to click it
  ("element is not enabled"). Click it with `force=True`.
- jamovi extends a selection with Cmd when `navigator.platform` is a Mac and
  Ctrl otherwise. Ctrl-click on macOS is a secondary click, and Playwright's
  `ControlOrMeta` did not extend the selection: choose the key from the
  platform.

## What the Spanish run showed

Running the unchanged recipe in Spanish found two things no headless test sees:

- **A LevelSelector label is never translated.** `levelselector.ts:64-72` renders
  `getPropertyValue('label')` as it is, while `gridcombobox.ts:82-86` and
  `gridtextbox.ts:124-128` pass it through `this.translate()`. The module's
  catalog has the translation; the panel shows English. Nothing in the module
  can fix it; the recipe has to accept the English label.
- **Longer labels overflow.** A `TextBox` with `width: large` after a Spanish
  label ran past the right edge of the panel (see the overflow line in
  `traps.md`). Capture once in each language the module ships.

## Videos

`jamovi_record.py` records a context with a visible cursor and writes `.mp4`,
`.vtt` and `.srt` whose captions are timed from the run itself. Measured: a
three-step walkthrough gave a 17.58 s video with its last cue ending at 17.56 s,
once the connection and loading before the first caption and the ~24 s the
recorder keeps running while the context closes are cut. The capture is
1440×900 and is scaled to 1152×720 at 12 fps; a larger viewport only adds empty
canvas, because jamovi's panes stop growing at about 1280 px.

## In a Quarto tutorial

- Embed screenshots as plain Markdown images with a figure id,
  `![Caption.](../screenshots/km-window.png){#fig-jamovi-km}`; they need no
  light/dark renderings (see `tutorial-site.md`).
- A `.py` file in the tutorial folder is not rendered or copied into `_site`
  (checked: only the PNGs the pages reference are).
- Commit the PNGs (tens of KB each) and the recipe; rerun it after UI changes and
  before a release, when the panel may have moved.
