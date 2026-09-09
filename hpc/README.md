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
rsync -av --exclude lib --exclude cmdstan_cache --exclude results \
  ./ <hpc>:/export/scratch/$USER/negative-response-conventions/
ssh <hpc>
cd /export/scratch/$USER/negative-response-conventions
sbatch hpc/run.units
```

`results/` is excluded from the sync deliberately: copy it across only if you
want the HPC to skip units already computed locally, and copy it back the same
way when the array finishes.

## Throughput

| tasks resident | wall clock for 4,200 units |
|---|---|
| 50 | ~29 h |
| 100 | ~15 h |
| 200 | ~7 h |

Assuming 20 minutes per unit on a dedicated core, which is between the 13
minutes measured idle locally and the 42 measured under contention. Confirm it
against the first few task logs before trusting the rest of the table.

## Collate

`analysis/collate.R` aggregates whatever result files exist, so it can be run
on a partial array:

```sh
singularity exec -B "$PWD":"$PWD" --pwd "$PWD" negative-response-conventions.sif \
  Rscript analysis/collate.R results/metrics.csv
```
