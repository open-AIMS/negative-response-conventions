# negative-response-conventions

A simulation study of what the common ways of handling negative response values
do to reported toxicity estimates, for responses that can legitimately fall
below zero — specific growth rate above all.

Six data-handling conventions are compared on simulated data where the true
ErC10, ErC50 and no-effect concentration are known by construction, so each can
be scored rather than merely compared. Every arm is fitted the way
[`bayesnec`](https://github.com/open-AIMS/bayesnec) recommends: model-averaged
over the declining candidate set, with package defaults throughout.

This compendium is the citable record behind the *Modelling growth data and
other potentially negative response values* vignette (`example7`) in
`bayesnec`.

## The conventions

| arm | what the analyst does | family |
|---|---|---|
| `measured` | use the values as recorded | gaussian |
| `floored` | replace negatives with zero | gaussian |
| `deleted` | delete the negative rows, keep the rest of their group | gaussian |
| `censored` | declare negatives left-censored at zero | gaussian |
| `beta` | floor, scale to (0, 1), fit a Beta | Beta |
| `gamma` | floor, fit a Gamma | Gamma |

No arm is handed a prior built by another, so a contrast between arms is the
contrast a practitioner would obtain rather than a likelihood-only contrast.

## Running it

Everything runs from the repository root.

```sh
Rscript analysis/run_block.R 1 20      # iterations 1-50 in every cell, 20 workers
Rscript analysis/collate.R             # aggregate whatever exists -> results/metrics.csv
Rscript analysis/run_block.R 2 20      # iterations 51-100
Rscript analysis/collate.R
```

Blocks are **balanced**: block 1 runs iterations 1–50 in every cell, not cell 1
to completion. That is what makes an early collation meaningful, and it is what
lets the vignette be drafted against 50 iterations and refreshed later without
any prose changing.

The run is **resumable**. Each `(cell, arm, iteration)` writes its own file
under `results/`, and a unit whose file already exists is skipped, so a crashed
block is restarted with the same command.

## Two things that are not optional

**`backend = "cmdstanr"`.** `brms` defaults to `rstan`, which recompiles every
model in every session. A single arm ran for ten minutes under `rstan` without
producing a fit. `fit_arm()` refuses to run unless
`cmdstanr_write_stan_file_dir` is set, because the cost of discovering this late
is days rather than minutes.

**The project library.** `lib/` holds the `bayesnec` build the study is about.
Every script puts it first on `.libPaths()`. Do not run against a different
installed version: the study exists to measure behaviour that changed in
2.2.0, and an older library silently measures the old behaviour.

## Provenance

- `bayesnec` built from `open-AIMS/bayesnec` at `0976caca` (`dev`), version
  2.1.3.33, installed into `lib/`.
- `R/simulate.R` is copied verbatim from
  [`open-AIMS/negative-sgr`](https://github.com/open-AIMS/negative-sgr) at
  `0181d66e`, so the generating model is demonstrably the same one the earlier
  study used.
- Nothing else is carried over. That study remains the frozen record of the
  results the vignette quoted before this one replaced them, and it is not
  modified.

## Layout

```
R/simulate.R     generating model (carried over, do not edit)
R/cells.R        the design cells and their truths
R/arms.R         the six conventions, and the fitting call
R/estimates.R    endpoint extraction, model weights, per-unit runner
analysis/        run_block.R, collate.R
results/         one .rds per (cell, arm, iteration); metrics.csv
lib/             project-local bayesnec
cmdstan_cache/   compiled Stan programs, keyed by code hash
```

`REDESIGN-claude.md` is the implementation specification: what the study must
establish, what changed from the previous design and why, the cell table, the
staging plan and its Monte Carlo standard errors, the metrics schema, and what
is out of scope. The collaborator-facing plan is
[open-AIMS/bayesnec#296](https://github.com/open-AIMS/bayesnec/issues/296).
