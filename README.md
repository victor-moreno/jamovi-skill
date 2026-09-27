# jamovi-module skill

A reusable skill for building jamovi modules, written from the experience of
building **SNPstats** (two analyses: descriptive/association/LD/haplotype, and a
polygenic score) and **snpImport** (a PLINK/VCF genotype importer), plus a
review of dev.jamovi.org and the jamovi source.

It deliberately does **not** re-teach the tutorial. It covers what is
undocumented, silent, or contradicts the docs — each claim carrying the
file:line or the measurement that proves it, so a future session can verify
rather than trust.

Verified against **jamovi 28.1.0.0, jmvtools 28.3 (jamovi-compiler 0.3.5),
jmvcore 2.7.38**, on 2026-08-05.

```
SKILL.md                              entry point: the shape of a module,
                                      the eight rules that cost the most
references/traps.md                   the whole checklist, one line each
references/lifecycle-and-results.md   .init/.run, restore, tables, state, plots
references/data-io.md                 output variables, transport ceilings,
                                      getting files in, Special Import
references/yaml-and-compiler.md       verified type enums and compiler quirks
references/ui-and-javascript.md       .u.yaml, jus 3.0 handlers, browse button
references/build-install-ship.md      building, docker, deps, check, submission
references/testing.md                 headless calls, oracles, goldens, refresh
references/docs-and-source-map.md     what the docs cover, where they are wrong,
                                      which source file answers what
references/tutorial-site.md           a Quarto tutorial site for a module
scripts/mirror-jamovi-docs.sh         local greppable copy of the jamovi docs
scripts/quarto-sandbox.sh             run Quarto where ~/Library is not writable
```

## Using it

As a Claude Code skill:

```bash
ln -s "$PWD" ~/.claude/skills/jamovi-module
```

Claude reads `SKILL.md` when a task touches jamovi modules and pulls in the
reference files it needs. It is equally usable as plain documentation — start
with `references/traps.md`.

## Keeping it honest

Every factual claim is either a file:line into the jamovi source or a
measurement. When a claim stops being true, fix it *and* say which version
changed it. Two claims here were already found to contradict the current
official docs; both were re-verified by compiling a throwaway module rather
than by argument.
