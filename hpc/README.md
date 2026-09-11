# Running this study on the HPC

The study is two arrays of independent units: 4,200 simulation units (7 cells ×
100 realisations × 6 conventions) and 24 case-study units (4 marine microalgal
growth tests × 6 conventions). Each is one fit on one dedicated core, and the
result of each is one `.rds` file, so a lost task costs that task and nothing
else.

## The container, and why it holds no bayesnec

The study runs inside the image built by the **bayesnec** repository,
`hpc/bayesnec-precompile.def`, which holds R, cmdstan, brms and the packages the
analysis loads, and deliberately does not hold bayesnec. The job installs
bayesnec from source at start-up, from the commit named in `hpc/bayesnec.lock`.

That is what lets one image serve both repositories and every branch. The
previous version of this study built its own image with bayesnec pinned inside
it, which meant a new image for every version of the package under test, and it
made the 700MB copy a per-run cost rather than a rare one.

Build the image in the bayesnec repository, not here:

```sh
cd ../bayesnec && ./hpc/build.sh
```

`hpc/image.lock` is a committed copy of the one that build writes. It records
which image produced the results, and every job refuses to run against an image
whose SHA does not match it. `hpc/deploy.sh` refuses if the two repositories'
copies have drifted. Rebuilding the image is a change that can alter published
numbers, so it is made deliberately rather than discovered afterwards.

The cluster's singularity refuses an unprivileged `--fakeroot` build, so the
image is built on a workstation and copied across. `deploy.sh` copies it only
when the cluster does not already hold the one `hpc/image.lock` records, which
makes it a rare cost rather than a per-run one.

## Settings

Nothing about your account is committed. Copy the template and edit:

```sh
cp hpc/local.conf.example hpc/local.conf     # gitignored
```

## Running it

```sh
./hpc/deploy.sh                  # copy, then submit
./hpc/deploy.sh --copy-only      # copy, submit yourself
```

`deploy.sh` exports the pinned bayesnec commit from a local checkout, syncs the
code and `priors/`, copies the image if the cluster does not have it, and
submits. `submit.sh` then chains:

| job | tasks | what it does |
|---|---|---|
| `run.warmup` | 42 | task 1 installs bayesnec; all 42 run one unit per cell and arm, which between them compile every distinct Stan program the simulation needs |
| `run.units` | 4,158 | the rest of the simulation, on a dependency behind the warm-up |
| `run.cases` | 24 | the case studies, on the same dependency |

The simulation waits on the warm-up because a cold compile cache under 200
concurrent tasks is the one failure mode that would waste a whole allocation.
The case studies wait on it only for the install: their Stan programs are their
own, so there is nothing for the warm-up to compile on their behalf.

Both arrays are idempotent. A unit whose result file exists is skipped, so a
failed or timed-out subset is recovered by resubmitting the same array.

## Why the priors are fixed, and why the case studies' are not

bayesnec derives its priors from the response, and brms writes them into the
Stan source as literals, so every realisation of a cell produced a textually
different program and recompiled — 5,622 programs for 406 units in an early run.
`priors/` holds one prior per cell and arm, derived by `analysis/build_priors.R`
from a reference realisation the study never analyses, which makes the program
identical across iterations so it compiles once. Those 42 files are tracked and
must be deployed: they are part of the record, not a cache.

The case studies take `bnec()`'s own defaults instead. Each dataset and arm is
fitted once, so there is no repetition for an identical program to save, and
taking the defaults is the practice the case studies exist to show.

## Collecting

```sh
rsync -a HOST:DEST/results/ results/
rsync -a HOST:DEST/results_cases/ results_cases/
Rscript analysis/collate.R
```

## One trap worth knowing

A stale `lib/` in the compendium root shadows whatever library a script is run
against, and does it silently. On 2026-09-11 that rebuilt the whole prior set
from a superseded version of the package with no error and no warning. The
scripts now prepend `lib/` only when it exists, and the jobs assert that the
bayesnec they loaded came from the job library and reports the version
`hpc/bayesnec.lock` names. If you are running anything here by hand, check which
bayesnec you have first.
