## Run exactly one (cell, arm, iteration) unit, chosen by index.
##
##   Rscript analysis/run_unit.R <index> [n_iterations]
##
## For the HPC, where one SLURM array task is one unit on one dedicated core.
## That is a better fit than the local runner's mclapply: 20 concurrent fits on
## one 22-core machine cost 42 worker-minutes per unit against the 13 measured
## on an idle machine, and the difference is contention. One task, one core, no
## contention.
##
## Idempotent by the same existence check the local runner uses, so a resubmitted
## array only redoes what is missing.

ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) stop("run from the compendium root")
## Only prepend the project library if it exists. Inside the container bayesnec
## is installed in the image and lib/ is deliberately not synced, so this must
## not fail or shadow when it is absent.
if (dir.exists(file.path(ROOT, "lib"))) {
  .libPaths(c(file.path(ROOT, "lib"), .libPaths()))
}
suppressMessages(library(bayesnec))
if (utils::packageVersion("bayesnec") < "2.1.3.33") {
  stop("bayesnec ", utils::packageVersion("bayesnec"), " from ",
       dirname(find.package("bayesnec")), "; this study needs >= 2.1.3.33")
}
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

## Compiled Stan programs are shared across tasks and named by a hash of the
## code, so a warm cache means only the first task per program compiles.
CACHE <- Sys.getenv("NRC_STAN_CACHE", file.path(path.expand("~"), ".cache", "nrc-stan"))
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
options(cmdstanr_write_stan_file_dir = CACHE)

args <- commandArgs(trailingOnly = TRUE)
idx <- as.integer(args[1])
n_iter <- as.integer(if (length(args) >= 2) args[2] else 100L)

cl_tab <- cells()
## Same iteration-major ordering as the local runner, so index N means the same
## unit either way and the two can be mixed.
queue <- do.call(rbind, lapply(seq_len(n_iter), function(it) {
  do.call(rbind, lapply(seq_len(nrow(cl_tab)), function(i) {
    data.frame(row = i, cell = cl_tab$cell[i], arm = arm_names(),
               iteration = it, stringsAsFactors = FALSE)
  }))
}))
if (idx < 1L || idx > nrow(queue)) {
  stop("index ", idx, " outside 1:", nrow(queue))
}
u <- queue[idx, ]
path <- file.path(ROOT, "results", u$cell, u$arm,
                  sprintf("iter_%04d.rds", u$iteration))
if (file.exists(path)) {
  cat("already done:", path, "\n"); quit(save = "no")
}
dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

# One realisation per cell and arm is kept whole, for posterior predictive
# checks and residual plots. Which one is decided by a fixed seed before any
# result is seen; see exemplar_iteration().
fit_path <- NULL
if (u$iteration == exemplar_iteration(u$cell, u$arm, n_iter)) {
  fit_path <- file.path(ROOT, "fits", sprintf("%s__%s.rds", u$cell, u$arm))
}

t0 <- Sys.time()
out <- try(run_one(cl_tab[u$row, ], u$iteration, u$arm, fit_path = fit_path),
           silent = TRUE)
if (inherits(out, "try-error")) {
  out <- list(cell = u$cell, iteration = u$iteration, arm = u$arm,
              record = list(arm = u$arm, estimable = FALSE,
                            note = conditionMessage(attr(out, "condition"))),
              estimates = NULL, weights = NULL)
}
saveRDS(out, path)
cat(sprintf("unit %d  %s/%s/iter %d  %.1f min\n", idx, u$cell, u$arm,
            u$iteration, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
