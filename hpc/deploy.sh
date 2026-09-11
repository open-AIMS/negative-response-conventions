#!/bin/bash
# Copy the study, the container and the pinned bayesnec source to the HPC, and
# submit the job chain.
#
#   ./hpc/deploy.sh              # copy and submit
#   ./hpc/deploy.sh --copy-only  # copy, submit yourself later
#
# Settings come from hpc/local.conf, which is gitignored; copy
# hpc/local.conf.example to it and edit. An account name, a login node and a
# path on someone's disk are not the repository's business, and an earlier
# version of this script had all three committed in a public repository.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

[ -f hpc/local.conf ] && . hpc/local.conf
: "${HOST:?set HOST in hpc/local.conf (see hpc/local.conf.example)}"
ACCOUNT="${HOST%@*}"
DEST="${DEST:-/export/scratch/$ACCOUNT/negative-response-conventions}"
BAYESNEC_REPO="${BAYESNEC_REPO:-../bayesnec}"
MAX_RESIDENT="${MAX_RESIDENT:-200}"
SIF_NAME="bayesnec-precompile.sif"

COMMIT=$(sed -n 's/^commit: //p' hpc/bayesnec.lock)
[ -n "$COMMIT" ] || { echo "no commit in hpc/bayesnec.lock" >&2; exit 1; }

# The image belongs to bayesnec and is built there. This repository commits a
# copy of its lock file so that the results record which image produced them,
# and the two must agree or the pair has drifted.
if [ -f "$BAYESNEC_REPO/hpc/image.lock" ]; then
  if ! diff -q hpc/image.lock "$BAYESNEC_REPO/hpc/image.lock" > /dev/null; then
    echo "hpc/image.lock differs from $BAYESNEC_REPO/hpc/image.lock" >&2
    diff hpc/image.lock "$BAYESNEC_REPO/hpc/image.lock" >&2 || true
    echo "Copy the bayesnec one across deliberately: it changes what the" >&2
    echo "results were produced with." >&2
    exit 1
  fi
fi

echo "==> exporting bayesnec $COMMIT from $BAYESNEC_REPO"
[ -d "$BAYESNEC_REPO/.git" ] || {
  echo "no git checkout at $BAYESNEC_REPO; set BAYESNEC_REPO in hpc/local.conf" >&2
  exit 1; }
git -C "$BAYESNEC_REPO" cat-file -e "$COMMIT^{commit}" 2>/dev/null || {
  echo "commit $COMMIT is not in $BAYESNEC_REPO; fetch it first" >&2; exit 1; }
rm -rf .bayesnec-src && mkdir -p .bayesnec-src
git -C "$BAYESNEC_REPO" archive "$COMMIT" | tar -x -C .bayesnec-src
grep -q "^Version: $(sed -n 's/^version: //p' hpc/bayesnec.lock)$" .bayesnec-src/DESCRIPTION || {
  echo "the exported source is not the version hpc/bayesnec.lock records" >&2; exit 1; }

echo "==> creating $DEST on $HOST"
ssh "$HOST" "mkdir -p $DEST/logs"

# priors/ is NOT excluded and must not be: those 42 files are what keep the Stan
# programs identical across iterations, which is what makes the study
# affordable. lib/ is excluded because the job builds it from the source below.
echo "==> syncing code, priors and R/"
rsync -a --delete-excluded \
  --exclude lib --exclude cmdstan_cache --exclude superceded \
  --exclude results --exclude results_cases --exclude '*.sif' --exclude '.git' \
  --exclude '*.log' --exclude 'hpc/local.conf' --exclude '.bayesnec-src' \
  ./ "$HOST:$DEST/"

echo "==> syncing the pinned bayesnec source"
rsync -a --delete .bayesnec-src/ "$HOST:$DEST/bayesnec-src/"

# The image changes only when a dependency changes, so it is copied only when
# the cluster does not already hold the one hpc/image.lock records.
WANT=$(sed -n 's/^sif_sha256: //p' hpc/image.lock)
HAVE=$(ssh "$HOST" "sha256sum $DEST/$SIF_NAME 2>/dev/null | cut -d' ' -f1" || true)
if [ "$WANT" != "$HAVE" ]; then
  : "${SIF:?the cluster does not hold the right image; set SIF in hpc/local.conf to a local copy}"
  [ -f "$SIF" ] || { echo "no image at $SIF. Build it in the bayesnec repository: ./hpc/build.sh" >&2; exit 1; }
  echo "==> copying the container ($(du -h "$SIF" | cut -f1)); this is slow and rare"
  rsync -a --progress "$SIF" "$HOST:$DEST/$SIF_NAME"
else
  echo "==> container already on the cluster and matching hpc/image.lock"
fi

if [ "${1:-}" = "--copy-only" ]; then
  cat <<TXT

Copied. To submit:
  ssh $HOST
  cd $DEST && ./hpc/submit.sh $MAX_RESIDENT
TXT
  exit 0
fi

echo "==> submitting"
# bash -lc so the module system is initialised: a non-login, non-interactive
# ssh has no sbatch on PATH.
ssh "$HOST" "bash -lc 'cd $DEST && chmod +x hpc/*.sh hpc/run.* && ./hpc/submit.sh $MAX_RESIDENT'"

cat <<TXT

Submitted. To check on it:

  ssh $HOST 'squeue -u \$USER'
  ssh $HOST 'find $DEST/results -name "*.rds" | wc -l'          # of 4200
  ssh $HOST 'find $DEST/results_cases -name "*.rds" | wc -l'    # of 24

To bring the results back:

  rsync -a "$HOST:$DEST/results/" results/
  rsync -a "$HOST:$DEST/results_cases/" results_cases/
TXT
