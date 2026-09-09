#!/bin/bash
# Copy the study and its container to the AIMS HPC and submit the job chain.
#
#   ./hpc/deploy.sh              # copy and submit
#   ./hpc/deploy.sh --copy-only  # copy, submit yourself later
#
# Run this from the compendium root on the local machine. It needs the .sif to
# have been built already (apptainer build, see hpc/README.md).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

HOST="${HOST:-rfisher@hpc-l001.aims.gov.au}"
DEST="${DEST:-/export/scratch/rfisher/negative-response-conventions}"
SIF="negative-response-conventions.sif"
MAX_RESIDENT="${MAX_RESIDENT:-200}"

if [ ! -f "$SIF" ]; then
  echo "no $SIF here. Build it first:" >&2
  echo "  apptainer build $SIF hpc/negative-response-conventions.def" >&2
  exit 1
fi

echo "==> creating $DEST on $HOST"
ssh "$HOST" "mkdir -p $DEST/logs"

# lib/ is excluded because bayesnec is in the image. priors/ is NOT excluded and
# must not be: those 42 files are what keep the Stan programs identical across
# iterations, which is what makes the study affordable.
echo "==> syncing code, priors and R/"
rsync -av --delete-excluded \
  --exclude lib --exclude cmdstan_cache --exclude superceded \
  --exclude results --exclude '*.sif' --exclude '.git' \
  --exclude '*.log' \
  ./ "$HOST:$DEST/"

echo "==> copying the container ($(du -h "$SIF" | cut -f1))"
rsync -av --progress "$SIF" "$HOST:$DEST/"

if [ "${1:-}" = "--copy-only" ]; then
  echo
  echo "copied. To submit:"
  echo "  ssh $HOST"
  echo "  cd $DEST && ./hpc/submit.sh $MAX_RESIDENT"
  exit 0
fi

echo "==> submitting"
# bash -lc so the module system is initialised: a non-login, non-interactive
# ssh has no sbatch on PATH.
ssh "$HOST" "bash -lc 'cd $DEST && chmod +x hpc/*.sh hpc/run.* && ./hpc/submit.sh $MAX_RESIDENT'"

cat <<TXT

Submitted. To check on it:

  ssh $HOST 'squeue -u rfisher'
  ssh $HOST 'find $DEST/results -name "*.rds" | wc -l'   # of 4200

To bring the results back when it finishes:

  rsync -av $HOST:$DEST/results/ ./results/
TXT
