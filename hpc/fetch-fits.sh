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

# Every directory the study saves fits into. Named in one place: adding a new
# one and forgetting it here returns a silent zero rather than an error, which
# is what happened when fits_disp/ was added.
DIRS="fits fits_cases fits_disp"
mkdir -p $DIRS
if [ $# -eq 0 ]; then
  for d in $DIRS; do
    rsync -a --info=progress2 "$HOST:$DEST/$d/" "$d/" 2>/dev/null || true
  done
else
  for n in "$@"; do
    got=no
    for d in $DIRS; do
      rsync -a "$HOST:$DEST/$d/$n.rds" "$d/" 2>/dev/null && { got=yes; break; }
    done
    [ "$got" = yes ] || { echo "no fit named $n on the cluster" >&2; exit 1; }
  done
fi
for d in $DIRS; do
  echo "$d: $(ls "$d"/*.rds 2>/dev/null | wc -l) fits"
done
