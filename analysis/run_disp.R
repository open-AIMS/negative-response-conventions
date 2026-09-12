## Can a dispersion sub-model mitigate what the response distribution does to
## the variance, for someone holding floored data that cannot be un-floored?
##
##   Rscript analysis/run_disp.R <index>     # 1..5
##
## Scoped deliberately. The posterior predictive check on the p1 exemplars found
## that the Gaussian conventions already describe the spread correctly -- their
## predicted SD is flat along the curve, as the data were generated -- so the
## question is not open for them. It is open for the bounded families, whose
## dispersion is tied to the mean and which an analyst reaches for precisely
## when the data have already been floored.
##
## `floored` with disp("loglinear") is included as the control: if the Gaussian
## variance model is already right, adding a dispersion sub-model should buy
## nothing, and showing that is worth as much as showing where it helps.
##
## Full treatment of this is issue #283.

ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) stop("run from the compendium root")
if (dir.exists(file.path(ROOT, "lib"))) {
  .libPaths(c(file.path(ROOT, "lib"), .libPaths()))
}
suppressMessages(library(bayesnec))
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

CACHE <- Sys.getenv("NRC_STAN_CACHE", file.path(path.expand("~"), ".cache", "nrc-stan"))
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
options(cmdstanr_write_stan_file_dir = CACHE)

queue <- data.frame(
  arm  = c("floored", "gamma",     "gamma", "beta",      "beta"),
  disp = c("loglinear", "loglinear", "power", "loglinear", "power"),
  stringsAsFactors = FALSE)

idx <- as.integer(commandArgs(trailingOnly = TRUE)[1])
if (is.na(idx) || idx < 1L || idx > nrow(queue)) stop("index outside 1:", nrow(queue))
u <- queue[idx, ]

CELL <- "p1"
cl <- cells()[cells()$cell == CELL, ]
it <- exemplar_iteration(CELL, u$arm)
path <- file.path(ROOT, "fits_disp", sprintf("%s__%s__%s.rds", CELL, u$arm, u$disp))
if (file.exists(path)) { cat("already have:", path, "\n"); quit(save = "no") }
dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

cat(sprintf("%s / %s / disp(%s), iteration %d\n", CELL, u$arm, u$disp, it))
t0 <- Sys.time()
# No fixed prior: a dispersion sub-model adds parameters the stored priors do
# not cover, so bnec() derives its own for this comparison.
dat <- cell_dataset(cl, it)
res <- fit_arm(dat, u$arm, seed = 333L + it, disp = u$disp, prior = NULL)
if (is.null(res$fit)) {
  cat("NOT ESTIMABLE:", res$record$note, "\n")
  saveRDS(list(record = res$record), path)
  quit(save = "no")
}
saveRDS(res$fit, path)
est <- arm_estimates(res$fit)
print(est, row.names = FALSE, digits = 4)
cat(sprintf("%.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
