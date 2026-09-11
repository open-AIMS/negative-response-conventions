#!/bin/bash
# Shared setup for every job in this study. Sourced, not executed.
#
# Defines where the study lives, checks that the container is the one this
# branch records, and builds the environment array that keeps the container's R
# away from the host's library. Nothing here installs anything: bayesnec is
# installed once by hpc/run.warmup into a library the array tasks then share,
# because 200 concurrent array tasks each running R CMD INSTALL would be 200
# copies of the same work racing for the same directory.

set -euo pipefail

# `module` returns non-zero where these are already loaded, which under `set -e`
# would end the job before it started.
module load slurm || true
module load singularity || true
command -v singularity > /dev/null || {
  echo "singularity not on PATH after 'module load singularity'" >&2; exit 1; }

STUDY="${NRC_STUDY:-/export/scratch/$USER/negative-response-conventions}"
cd "$STUDY"
mkdir -p logs

SIF="$STUDY/bayesnec-precompile.sif"
LIB="$STUDY/lib"
SRC="$STUDY/bayesnec-src"

# The image is half of what determines the results, so a job refuses to run
# against one the branch does not record. The same refusal as bayesnec's
# hpc/run.precompile, and for the same reason: rebuilding the image is a change
# that can alter published numbers and has to be made deliberately.
[ -f "$SIF" ] || { echo "no container at $SIF" >&2; exit 1; }
lock_sha=$(sed -n 's/^sif_sha256: //p' hpc/image.lock)
have_sha=$(sha256sum "$SIF" | cut -d' ' -f1)
if [ "$lock_sha" != "$have_sha" ]; then
  echo "image does not match hpc/image.lock" >&2
  echo "  hpc/image.lock: $lock_sha" >&2
  echo "  $SIF: $have_sha" >&2
  echo "Copy the image this branch records, or rebuild it in the bayesnec" >&2
  echo "repository and update both hpc/image.lock files." >&2
  exit 1
fi

# apptainer bind-mounts $HOME, so without this the container's R reads the
# account's own library and startup files from the host and can load a bayesnec
# that is not the one installed here. Verified on 2026-09-10 in bayesnec #308:
# an image built with no bayesnec in it reported bayesnec as available.
# R_LIBS_SITE is emptied for the same reason; --cleanenv would close the class
# but would also strip the SLURM_ variables these jobs read.
RENV=(--env R_LIBS="$LIB" --env R_LIBS_USER="$LIB" --env R_LIBS_SITE=
      --env R_ENVIRON_USER=/dev/null --env R_PROFILE_USER=/dev/null)

# Shared across tasks, nodes and runs: cmdstanr names a compiled program after a
# hash of its Stan source, so with the priors fixed per cell and arm there are a
# few hundred distinct programs for the whole study and they are worth compiling
# once. Keyed on the toolchain rather than the whole image, because the base
# image and cmdstan decide the binary and an R package change should not discard
# a warm cache. Same reasoning as bayesnec's hpc/run.precompile.
TOOLCHAIN=$( { sed -n 's/^base_digest: //p' hpc/image.lock
               sed -n 's/^cmdstan: //p' hpc/image.lock; } | sha256sum | cut -c1-16)
CACHE="${NRC_STAN_CACHE:-/export/scratch/$USER/nrc-stan-cache/$TOOLCHAIN}"
mkdir -p "$CACHE"

# Run one Rscript inside the container with the study bound and the host's R
# libraries kept out.
nrc_r() {
  singularity exec -B "$STUDY":"$STUDY" -B "$CACHE":"$CACHE" --pwd "$STUDY" \
    "${RENV[@]}" --env NRC_STAN_CACHE="$CACHE" "$SIF" Rscript "$@"
}

# Assert that the bayesnec about to be loaded is the one the study pins, and
# that it resolved to the job library rather than to something the host bound
# in. Called by every job before it spends any sampling time.
nrc_check_bayesnec() {
  local want_version
  want_version=$(sed -n 's/^version: //p' hpc/bayesnec.lock)
  singularity exec -B "$STUDY":"$STUDY" --pwd "$STUDY" "${RENV[@]}" \
    --env NRC_JOB_LIB="$LIB" --env NRC_WANT_VERSION="$want_version" "$SIF" \
    Rscript -e '
      lib <- normalizePath(Sys.getenv("NRC_JOB_LIB"))
      p <- find.package("bayesnec")
      if (!identical(normalizePath(dirname(p)), lib))
        stop("bayesnec resolved to ", p, ", not the job library ", lib)
      v <- as.character(packageVersion("bayesnec"))
      if (!identical(v, Sys.getenv("NRC_WANT_VERSION")))
        stop("bayesnec ", v, " installed, but hpc/bayesnec.lock pins ",
             Sys.getenv("NRC_WANT_VERSION"))
      cat("bayesnec", v, "from", p, "\n")'
}
