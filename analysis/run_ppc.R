## Refit one unit and record only the predicted-against-observed spread.
##
##   Rscript analysis/run_ppc.R <index> [n_iterations]
##
## Written to results_ppc/ so that results/ and results_disp/, which are
## published, are not touched. The fits are deterministic given the cell, the
## iteration and the fixed prior, so this reproduces the unit the study recorded
## and adds a statistic to it rather than producing a different one.

ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) stop("run from the compendium root")
if (dir.exists(file.path(ROOT, "lib"))) .libPaths(c(file.path(ROOT, "lib"), .libPaths()))
suppressMessages(library(bayesnec))
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

CACHE <- Sys.getenv("NRC_STAN_CACHE", file.path(path.expand("~"), ".cache", "nrc-stan"))
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
options(cmdstanr_write_stan_file_dir = CACHE)

## The arms whose variance model is in question, plus `measured` as the
## reference: it is correctly specified by construction, so what it reports is
## the floor this statistic can reach on these data.
PPC_ARMS <- c("measured", "floored", "gamma", "beta",
              "floored_ll", "gamma_ll", "gamma_pw", "beta_ll", "beta_pw")

args <- commandArgs(trailingOnly = TRUE)
idx <- as.integer(args[1])
n_iter <- as.integer(if (length(args) >= 2) args[2] else 100L)
queue <- do.call(rbind, lapply(seq_len(n_iter), function(it) {
  do.call(rbind, lapply(disp_cells(), function(cc) {
    data.frame(cell = cc, arm = PPC_ARMS, iteration = it, stringsAsFactors = FALSE)
  }))
}))
if (is.na(idx) || idx < 1L || idx > nrow(queue)) stop("index outside 1:", nrow(queue))
u <- queue[idx, ]
path <- file.path(ROOT, "results_ppc", u$cell, u$arm, sprintf("iter_%04d.rds", u$iteration))
if (file.exists(path)) { cat("already done:", path, "\n"); quit(save = "no") }
dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

cl <- cells()[cells()$cell == u$cell, ]
dat <- cell_dataset(cl, u$iteration)
is_disp <- u$arm %in% disp_arms()$arm
t0 <- Sys.time()
res <- try({
  if (is_disp) {
    spec <- disp_arms()[disp_arms()$arm == u$arm, ]
    fit_arm(dat, spec$base_arm, seed = 333L + u$iteration, disp = spec$disp,
            prior = prior_for(u$cell, u$arm, "priors_disp"))
  } else {
    fit_arm(dat, u$arm, seed = 333L + u$iteration, disp = "none",
            prior = prior_for(u$cell, u$arm, "priors"))
  }
}, silent = TRUE)

out <- list(cell = u$cell, arm = u$arm, iteration = u$iteration,
            sigma_generated = cl$sigma_0_abs, spread = NULL, note = NA_character_)
if (inherits(res, "try-error") || is.null(res$fit)) {
  out$note <- if (inherits(res, "try-error")) conditionMessage(attr(res, "condition")) else res$record$note
} else {
  out$spread <- ppc_spread(res$fit, scale = ppc_scale(dat, u$arm))
}
saveRDS(out, path)
cat(sprintf("ppc %d  %s/%s/iter %d  %.1f min\n", idx, u$cell, u$arm, u$iteration,
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
