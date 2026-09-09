# Running the study on the AIMS HPC

The study is embarrassingly parallel: 4,200 independent units for 100
iterations, each writing its own result file. One SLURM array task runs one
unit on one dedicated core.

## Why not the local runner

`analysis/run_block.R` uses `mclapply` across 20 workers on one machine. That
measured **42 worker-minutes per unit** against the **13 minutes** the same fit
took on an idle core — the difference is contention for memory bandwidth on a
saturated 22-core machine. One task per core removes it, so the HPC is faster
per unit as well as wider.

## Build the image

Built locally with `apptainer` and copied across, rather than pulled on the
HPC, because it pins `bayesnec` to a specific commit:

```sh
apptainer build negative-response-conventions.sif hpc/negative-response-conventions.def
scp negative-response-conventions.sif <hpc>:/export/scratch/$USER/negative-response-conventions/
```

## Submit

```sh
rsync -av --exclude lib --exclude cmdstan_cache --exclude superceded \
  --exclude results --exclude '*.sif' \
  ./ <hpc>:/export/scratch/$USER/negative-response-conventions/
scp negative-response-conventions.sif \
  <hpc>:/export/scratch/$USER/negative-response-conventions/
ssh <hpc>
cd /export/scratch/$USER/negative-response-conventions
./hpc/submit.sh 200
```

`lib/` is excluded because `bayesnec` lives in the image; `run_unit.R` only
prepends `lib/` when it exists, so its absence is correct rather than a
fallback. `priors/` **is** synced and must be: those 42 files are what make the
Stan programs identical across iterations.

`results/` is excluded deliberately. Copy it across only if you want the HPC to
skip units already computed locally, and copy it back the same way when the
array finishes.

## Two stages, and why

`submit.sh` chains a 42-task warm-up before the main array, using
`--dependency=afterok`.

Units 1-42 are exactly one per cell and arm, because the queue is
iteration-major and there are 7 cells x 6 arms. With the priors fixed, those 42
units compile every Stan program the remaining 4,158 will ever need. The main
array then only reads the cache.

Without that, 200 tasks would start on a cold cache and write the same files to
the same paths simultaneously; `cmdstanr` does not lock. It is the one failure
mode that could waste a whole allocation.

## Throughput

| tasks resident | wall clock for 4,200 units |
|---|---|
| 50 | ~29 h |
| 100 | ~15 h |
| 200 | ~7 h |

Assuming 20 minutes per unit on a dedicated core, which was measured *before*
the priors were fixed and therefore includes compiling about 14 Stan programs
per unit. With the compile cache warm, a unit is sampling only and should be
substantially quicker. Confirm against the first few task logs before trusting
any of this table -- every previous estimate in this study has been wrong in the
optimistic direction.

## Collate

`analysis/collate.R` aggregates whatever result files exist, so it can be run
on a partial array:

```sh
singularity exec -B "$PWD":"$PWD" --pwd "$PWD" negative-response-conventions.sif \
  Rscript analysis/collate.R results/metrics.csv
```
