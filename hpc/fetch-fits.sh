#!/bin/bash
# Bring the saved fits back from the cluster.
#
#   ./hpc/fetch-fits.sh              # everything, about 700MB
#   ./hpc/fetch-fits.sh p1__gamma    # one, by name
#
# They are not tracked: 66 model-averaged fits at about 11MB each is not
# something to put in a repository, and every one of them is reproducible from
# the code, the priors and hpc/bayesnec.lock. What they save is the hour of
# fitting, which is the point when the question is a posterior predictive check
# rather than a number.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[ -f hpc/local.conf ] && . hpc/local.conf
: "${HOST:?set HOST in hpc/local.conf}"
ACCOUNT="${HOST%@*}"
DEST="${DEST:-/export/scratch/$ACCOUNT/negative-response-conventions}"

mkdir -p fits fits_cases
if [ $# -eq 0 ]; then
  rsync -a --info=progress2 "$HOST:$DEST/fits/" fits/
  rsync -a --info=progress2 "$HOST:$DEST/fits_cases/" fits_cases/
else
  for n in "$@"; do
    rsync -a "$HOST:$DEST/fits/$n.rds" fits/ 2>/dev/null \
      || rsync -a "$HOST:$DEST/fits_cases/$n.rds" fits_cases/ \
      || { echo "no fit named $n on the cluster" >&2; exit 1; }
  done
fi
echo "have: $(ls fits fits_cases 2>/dev/null | grep -c '\.rds$') fits"
