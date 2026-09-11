#!/bin/bash
# Submit the study: warm-up array, then the simulation on a dependency, and the
# case studies alongside.
#
#   ./hpc/submit.sh [MAX_RESIDENT]
#
# The simulation waits on the warm-up because a cold compile cache under 200
# concurrent tasks is the one failure mode that would waste a whole allocation,
# and because the warm-up is what installs bayesnec. The case studies wait on it
# for the install alone: their Stan programs are their own, so there is no cache
# for the warm-up to fill on their behalf.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# sbatch is not on PATH in a non-interactive shell on this cluster; it comes
# from a module. A plain `ssh host ./hpc/submit.sh` therefore failed with
# "sbatch: command not found" and submitted nothing.
if ! command -v sbatch > /dev/null 2>&1; then
  module load slurm 2>/dev/null || true
fi
command -v sbatch > /dev/null 2>&1 || {
  echo "sbatch not on PATH even after 'module load slurm'" >&2; exit 1; }
MAX_RESIDENT="${1:-200}"
mkdir -p logs

WARM=$(sbatch --parsable hpc/run.warmup)
echo "warm-up:     $WARM  (42 units, one per cell and arm; task 1 installs bayesnec)"

MAIN=$(sbatch --parsable --dependency=afterok:"$WARM" \
       --array=43-4200%"$MAX_RESIDENT" hpc/run.units)
echo "simulation:  $MAIN  (units 43-4200, $MAX_RESIDENT resident)"

CASES=$(sbatch --parsable --dependency=afterok:"$WARM" hpc/run.cases)
echo "case studies: $CASES  (24 units)"

cat <<TXT

watch:      squeue -u \$USER
simulation: find results -name '*.rds' | wc -l         # of 4200
cases:      find results_cases -name '*.rds' | wc -l   # of 24
TXT
