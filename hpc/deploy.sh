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

FRESH=no
ARGS=()
for a in "$@"; do
  case "$a" in
    --fresh) FRESH=yes ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- "${ARGS[@]:-}"

# Results already on the cluster are the trap this guards. Both runners skip a
# unit whose result file exists, which is what makes a resubmitted array cheap;
# it also means results produced by a different bayesnec would be silently
# adopted as this run's. The job directory records which commit produced what is
# in it, and a mismatch stops the deployment rather than mixing the two.
REMOTE_COMMIT=$(ssh "$HOST" "sed -n 's/^bayesnec_commit: //p' $DEST/PROVENANCE 2>/dev/null" || true)
REMOTE_RESULTS=$(ssh "$HOST" "find $DEST/results $DEST/results_cases -name '*.rds' 2>/dev/null | wc -l" || echo 0)
if [ "$REMOTE_RESULTS" -gt 0 ] && [ "$REMOTE_COMMIT" != "$COMMIT" ]; then
  if [ "$FRESH" != "yes" ]; then
    cat >&2 <<TXT
$DEST holds $REMOTE_RESULTS result files produced by
  ${REMOTE_COMMIT:-an unrecorded commit}
and this deployment pins
  $COMMIT

Both runners skip a unit whose result file exists, so submitting now would adopt
those as though they belonged to this run. Archive them, or re-run with --fresh
to delete them on the cluster:

  ./hpc/deploy.sh --fresh
TXT
    exit 1
  fi
  # Moved aside, not deleted. These are the only copy of the per-unit records
  # from the previous run -- the archived tables are summaries of them -- and at
  # 107MB against 735TB free there is nothing to gain by removing them. The
  # retired image and the stale library do go, because neither is a record.
  STAMP="superseded-$(date +%Y%m%d-%H%M%S)"
  echo "==> --fresh: moving $REMOTE_RESULTS result files aside into $STAMP/"
  ssh "$HOST" "set -e
    mkdir -p $DEST/$STAMP
    for d in results results_cases; do
      [ -d $DEST/\$d ] && mv $DEST/\$d $DEST/$STAMP/\$d || true
    done
    [ -f $DEST/PROVENANCE ] && mv $DEST/PROVENANCE $DEST/$STAMP/ || true
    rm -rf $DEST/lib $DEST/negative-response-conventions.sif
    printf 'moved aside by deploy.sh on %s, superseded by bayesnec %s\n' \
      '$(date -Is)' '$COMMIT' > $DEST/$STAMP/README"
fi

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
# Asked of git rather than tested as a directory: in a git worktree .git is a
# file pointing at the main repository, so a -d test rejects a perfectly good
# checkout.
git -C "$BAYESNEC_REPO" rev-parse --git-dir > /dev/null 2>&1 || {
  echo "no git checkout at $BAYESNEC_REPO; set BAYESNEC_REPO in hpc/local.conf" >&2
  exit 1; }
git -C "$BAYESNEC_REPO" cat-file -e "$COMMIT^{commit}" 2>/dev/null || {
  echo "commit $COMMIT is not in $BAYESNEC_REPO; fetch it first" >&2; exit 1; }
rm -rf .bayesnec-src && mkdir -p .bayesnec-src
git -C "$BAYESNEC_REPO" archive "$COMMIT" | tar -x -C .bayesnec-src
grep -q "^Version: $(sed -n 's/^version: //p' hpc/bayesnec.lock)$" .bayesnec-src/DESCRIPTION || {
  echo "the exported source is not the version hpc/bayesnec.lock records" >&2; exit 1; }

echo "==> creating $DEST on $HOST"
ssh "$HOST" "mkdir -p $DEST"

# priors/ is NOT excluded and must not be: those 42 files are what keep the Stan
# programs identical across iterations, which is what makes the study
# affordable. lib/ is excluded because the job builds it from the source below.
#
# --delete, NOT --delete-excluded. The two are opposites for the paths named
# below: --delete leaves an excluded path on the receiver alone, while
# --delete-excluded goes out of its way to remove it. This script used the
# second, so every --exclude here was an instruction to delete rather than to
# protect. On 2026-09-12 that removed logs/, lib/, results/, results_cases/ and
# the superseded-*/ archive of the previous run from the cluster in one command.
# The Stan cache survived only because it lives outside the job directory.
echo "==> syncing code, priors and R/"
rsync -a --delete \
  --exclude lib --exclude cmdstan_cache --exclude superceded \
  --exclude results --exclude results_cases --exclude fits --exclude fits_cases \
  --exclude logs --exclude 'superseded-*' --exclude bayesnec-src --exclude PROVENANCE \
  --exclude '*.sif' --exclude '.git' \
  --exclude '*.log' --exclude 'hpc/local.conf' --exclude '.bayesnec-src' \
  ./ "$HOST:$DEST/"

# After the sync, not before: the rsync above would delete it.
ssh "$HOST" "mkdir -p $DEST/logs"

echo "==> recording provenance"
ssh "$HOST" "printf 'bayesnec_commit: %s\nimage_sha256: %s\ndeployed: %s\n' \
  '$COMMIT' '$(sed -n 's/^sif_sha256: //p' hpc/image.lock)' '$(date -Is)' > $DEST/PROVENANCE"

echo "==> syncing the pinned bayesnec source"
rsync -a --delete .bayesnec-src/ "$HOST:$DEST/bayesnec-src/"

# The image changes only when a dependency changes, so it is copied only when
# the cluster does not already hold the one hpc/image.lock records.
WANT=$(sed -n 's/^sif_sha256: //p' hpc/image.lock)
HAVE=$(ssh "$HOST" "sha256sum $DEST/$SIF_NAME 2>/dev/null | cut -d' ' -f1" || true)
# Before uploading 700MB, look for the image the cluster may already hold from a
# bayesnec precompile run. A copy within scratch is seconds; the upload is not.
if [ "$WANT" != "$HAVE" ]; then
  FOUND=$(ssh "$HOST" "for f in \$(find /export/scratch/\$USER -maxdepth 3 -name '$SIF_NAME' 2>/dev/null); do
             if [ \"\$(sha256sum \$f | cut -d' ' -f1)\" = '$WANT' ]; then echo \$f; break; fi
           done" || true)
  if [ -n "$FOUND" ]; then
    echo "==> the cluster already holds a matching image; copying it within scratch"
    ssh "$HOST" "cp '$FOUND' $DEST/$SIF_NAME"
    HAVE="$WANT"
  fi
fi
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
