# The options panel and its JavaScript

## The two files, and how they connect

`jamovi/<analysis>.u.yaml` lays the panel out; `jamovi/js/<analysis>.js` gives it
behaviour. **The two must share a basename**, because the UI compiler emits
`this.handlers = require('./<basename>')` into the generated `.src.js` from the
*file* basename — mismatch them and the handlers are not wired up at all.
Lower case is the convention (and what jmv uses), but the case itself is not
load-bearing: see SKILL.md for why the "camelCase breaks the panel on Linux"
rule that used to live here was wrong.

There is a second, different mechanism — `<name>.events.js` — which is loaded
**only** when the `.u.yaml` declares an explicit `events:` block referencing
`./＜name＞.events::＜export＞`. An empty `<name>.events.js` sitting next to the
real handler file reads as if it were live and is a good way to waste an hour;
delete it if you are not using the `events:` block.

Requirements:

```yaml
name: myanalysis
title: My Analysis
jus: '3.0'          # < 3.0 and none of the handlers load
compilerMode: tame  # or the compiler overwrites your layout on every build
children: ...
```

## Handlers

CommonJS, one object on `module.exports`, functions named
`{optionName}_{eventName}` plus view-level handlers:

```js
module.exports = {
    view_loaded:  function(ui, event) { setup(ui); },
    view_updated: function(ui, event) { setup(ui); },
    method_changed: function(ui, event) {
        if (ui.method.value() === 'welchs') ui.priorWidth.setValue(0.707);
    }
};
```

- `creating` — before anything is in the DOM.
- `loaded` — **once per panel type, not once per analysis.** The same panel
  object is reused for every analysis of that type for as long as jamovi runs.
- `updated` — when the user selects a different analysis of the same type, or
  inserts a new one while a panel already exists. **Anything that must reflect
  the current analysis's option values belongs here as well as in `loaded`**, or
  it will show the previous analysis's state.
- `changing` / `changed` on any control; `listItemAdded` / `listItemRemoved` on
  ListBox; `updated` on Suppliers.
- A `Supplier`/`VariableSupplier` with `populate: 'manual'` **requires** an
  `updated` handler; jamovi raises an explicit error if it is missing.

Handlers are `(ui, event)`. `ui` carries every control as a property, and `this`
is the handlers object, so auxiliary functions can be methods on it.

## Setting an option that has no control

Hidden options render no control, so `ui.<name>.setValue()` does not exist. The
robust sequence, which also survives jamovi version differences:

```js
function setOpt(ui, name, value) {
    if (ui[name] && typeof ui[name].setValue === 'function') return ui[name].setValue(value);
    if (typeof ui.setOptionValue === 'function')             return ui.setOptionValue(name, value);
    if (typeof ui.getOption === 'function') {
        var opt = ui.getOption(name);
        if (opt && typeof opt.setValue === 'function') opt.setValue(value);
    }
}
```

Read them back the same way (`ctrl.value()` → `ui.getOptionValue(name)` →
`ui.getOption(name).value()`). Prefer the **options model over the DOM**: on the
first `view_loaded` of a restored analysis the input may not have been populated
yet, and reading `$input.val()` there gives you an empty string for an analysis
that does have a value.

## The file-browse pattern

The only way to get a file into an analysis (see `data-io.md` for why). Shape:

1. A visible, **disabled** TextBox bound to a `filename` String option — a
   passive readout, not an input. Use the native `disabled` attribute rather than
   hand-styled grey, so the platform greys it and it stays legible in the dark
   theme. Re-assert it on every `view_updated`.
2. A button injected next to that input, guarded so it is injected once:
   `if ($input.prev('.my-browse-btn').length === 0) { … }`. Test on the side you
   actually inserted — getting `prev`/`next` backwards re-injects a button on
   every update.
3. `document.createElement('input'); type = 'file'` created on click, appended
   hidden, `.click()`ed, removed in the change handler.
4. `FileReader.readAsDataURL` (then slice after the comma) or `File.slice()` +
   `CompressionStream('gzip')` for big files, into a **hidden String option**.
5. On error, write an empty payload and a visible message. **Never fall back to
   writing a path.**

Get jQuery from the control rather than assuming a global:
`var jq = $input.constructor;`.

Anything that must survive a restore (showing the filename field only when there
is a name) goes *outside* the injection guard, so it runs on every
`view_updated`.

### Slicing on the browser side

If the payload is a subset of a large file, do the byte selection in JS and the
semantics in R: JS computes offsets and slices, R parses and validates. Two
reasons — the browser is the only place with the file, and R is where the tests
and the hardening are. Do not let format knowledge leak into the panel beyond
what selecting bytes requires.

Enforce the transport ceiling here, before sending, and tell the user; nothing
downstream will (`data-io.md`).

## Debugging

- jamovi ships Chrome DevTools: **F10**. If the keystroke does not register,
  click the blue bar at the top to move focus out of the iframe first.
- Enable **Developer Mode** (app menu → three dots) for R stack traces in the
  results panel instead of a generic error.
- A panel that renders but has no injected controls is **not** the
  lowercase-filename bug — that one is a myth, see SKILL.md. Look instead at a
  basename mismatch between the `.u.yaml` and `js/<name>.js` (the generated
  `require` then points at nothing), a throw while the panel is being built, or
  a stray identifier. Only running the panel shows any of these; grepping the
  file does not.

## Testing the panel

Two layers, and the second is the one that catches real breakage:

- **Source-level**: grep/parse the file for the handlers and options it must
  reference. Cheap, catches renames.
- **Behavioural**: inject the panel into a jQuery stand-in and *click the
  buttons* against real fixtures. A Load button has shipped dead twice here —
  once from a throw while building it, once from a stray identifier in its body
  — and only this layer saw either.

Join the two halves by having the JS tests **dump the options they produced** to
disk, and the R tests run the analysis on those dumps. Every other R test builds
its own payloads, and so cannot catch a browser that slices the wrong bytes.
