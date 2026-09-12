## Run one dispersion-sweep unit, chosen by index.
##
##   Rscript analysis/run_disp_sweep.R <index> [n_iterations]
##
## Separate from the study's own runner and writing to results_disp/, so that
## adding these arms cannot renumber or disturb a completed run.

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

args <- commandArgs(trailingOnly = TRUE)
idx <- as.integer(args[1])
n_iter <- as.integer(if (length(args) >= 2) args[2] else 100L)
queue <- disp_queue(n_iter)
if (is.na(idx) || idx < 1L || idx > nrow(queue)) {
  stop("index ", args[1], " outside 1:", nrow(queue))
}
u <- queue[idx, ]
path <- file.path(ROOT, "results_disp", u$cell, u$arm,
                  sprintf("iter_%04d.rds", u$iteration))
if (file.exists(path)) { cat("already done:", path, "\n"); quit(save = "no") }
dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

# One realisation per cell and arm is kept whole, chosen by the same seeded draw
# the study uses, for posterior predictive checks.
fit_path <- NULL
if (u$iteration == exemplar_iteration(u$cell, u$arm, n_iter)) {
  fit_path <- file.path(ROOT, "fits_disp",
                        sprintf("%s__%s.rds", u$cell, u$arm))
}

t0 <- Sys.time()
out <- try({
  o <- run_disp_unit(u$cell, u$arm, u$iteration)
  o
}, silent = TRUE)
if (inherits(out, "try-error")) {
  out <- list(cell = u$cell, iteration = u$iteration, arm = u$arm,
              record = list(arm = u$arm, estimable = FALSE,
                            note = conditionMessage(attr(out, "condition"))),
              estimates = NULL, weights = NULL, diagnostics = NULL)
}
saveRDS(out, path)
cat(sprintf("disp unit %d  %s/%s/iter %d  %.1f min\n", idx, u$cell, u$arm,
            u$iteration, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
