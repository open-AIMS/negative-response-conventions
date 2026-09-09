#!/bin/bash
# Submit the study: warm-up array, then the main array on a dependency.
#
#   ./hpc/submit.sh [MAX_RESIDENT]
#
# Chained the same way as ssdsims-org/test_run/poc-hpc: the main array does not
# start unless the warm-up succeeded, because a cold compile cache under 200
# concurrent tasks is the one failure mode that would waste a whole allocation.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
MAX_RESIDENT="${1:-200}"
mkdir -p logs

WARM=$(sbatch --parsable hpc/run.warmup)
echo "warm-up job:  $WARM  (42 units, one per cell and arm)"

MAIN=$(sbatch --parsable --dependency=afterok:"$WARM" \
       --array=43-4200%"$MAX_RESIDENT" hpc/run.units)
echo "main job:     $MAIN  (units 43-4200, $MAX_RESIDENT resident)"
echo
echo "watch:    squeue -u \$USER"
echo "progress: find results -name '*.rds' | wc -l   # of 4200"
echo "collate:  singularity exec -B \$PWD:\$PWD --pwd \$PWD \\"
echo "            negative-response-conventions.sif Rscript analysis/collate.R"
