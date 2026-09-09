#!/bin/bash
# Extend the study to a larger iteration target, chaining as many arrays as the
# cluster's MaxArraySize requires.
#
#   ./hpc/extend.sh <target_iterations> [first_unit] [after_job] [max_resident]
#
# Example: ./hpc/extend.sh 500 4201 891894 200
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
command -v sbatch > /dev/null 2>&1 || module load slurm 2>/dev/null || true

TARGET="${1:-500}"; FIRST="${2:-4201}"; AFTER="${3:-}"; MAXRES="${4:-200}"
UNITS_PER_ITER=42
LAST=$(( TARGET * UNITS_PER_ITER ))
CHUNK=10000                      # MaxArraySize - 1 on this cluster

echo "extending to $TARGET iterations = $LAST units; submitting $FIRST..$LAST"
dep=""
[ -n "$AFTER" ] && dep="--dependency=afterany:$AFTER"

start=$FIRST
while [ "$start" -le "$LAST" ]; do
  n=$(( LAST - start + 1 )); [ "$n" -gt "$CHUNK" ] && n=$CHUNK
  offset=$(( start - 1 ))
  jid=$(sbatch --parsable $dep \
        --array=1-"$n"%"$MAXRES" \
        --export=ALL,UNIT_OFFSET="$offset",N_ITER="$TARGET" \
        hpc/run.extend)
  echo "  units $start-$(( start + n - 1 ))  ->  job $jid"
  dep="--dependency=afterany:$jid"
  start=$(( start + n ))
done
