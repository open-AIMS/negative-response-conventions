## Aggregate whatever result files exist into the metrics table.
##
##   Rscript analysis/collate.R [outfile]
##
## Deliberately aggregates what is on disk rather than what was planned, so it
## can be run after any block. It reports `n_used` per row, and every figure the
## report draws must come from this table rather than being typed, so that a
## refresh at 100 or 200 iterations changes the numbers without touching prose.

ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) stop("run from the compendium root")
.libPaths(c(file.path(ROOT, "lib"), .libPaths()))
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

args <- commandArgs(trailingOnly = TRUE)
outfile <- if (length(args)) args[1] else file.path(ROOT, "results", "metrics.csv")

files <- list.files(file.path(ROOT, "results"), "^iter_\\d+\\.rds$",
                    recursive = TRUE, full.names = TRUE)
if (!length(files)) stop("no result files under results/")
cat("collating", length(files), "result files\n")

rows <- lapply(files, function(f) {
  o <- readRDS(f)
  base <- data.frame(cell = o$cell, arm = o$arm, iteration = o$iteration,
                     estimable = isTRUE(o$record$estimable),
                     n_altered = o$record$n_altered %||% NA_integer_,
                     n_removed = o$record$n_removed %||% NA_integer_,
                     stringsAsFactors = FALSE)
  if (is.null(o$estimates)) {
    return(cbind(base[rep(1, length(ESTIMATES)), ],
                 data.frame(estimate = ESTIMATES, value = NA_real_,
                            lower = NA_real_, upper = NA_real_)))
  }
  cbind(base[rep(1, nrow(o$estimates)), ], o$estimates)
})
raw <- do.call(rbind, rows)

cl_tab <- cells()
truth <- do.call(rbind, lapply(seq_len(nrow(cl_tab)), function(i) {
  tv <- cell_truth(cl_tab[i, ])$true_values
  data.frame(cell = cl_tab$cell[i], estimate = names(tv), truth = unname(tv),
             stringsAsFactors = FALSE)
}))
raw <- merge(raw, truth, by = c("cell", "estimate"), all.x = TRUE)

## Monte Carlo standard errors, because a collation at 50 iterations must not be
## read as if it were one at 200. A proportion's MCSE is sqrt(p(1-p)/n); a
## mean's is sd/sqrt(n).
mcse_prop <- function(p, n) sqrt(p * (1 - p) / n)
mcse_mean <- function(x) stats::sd(x) / sqrt(length(x))

metrics <- do.call(rbind, lapply(split(raw, list(raw$cell, raw$arm, raw$estimate),
                                       drop = TRUE), function(g) {
  ok <- !is.na(g$value)
  n_used <- sum(ok)
  if (!n_used) {
    return(data.frame(cell = g$cell[1], arm = g$arm[1], estimate = g$estimate[1],
                      truth = g$truth[1], n_run = nrow(g), n_used = 0L,
                      bias = NA_real_, bias_mcse = NA_real_, rel_bias = NA_real_,
                      rmse = NA_real_, coverage = NA_real_,
                      coverage_mcse = NA_real_, width = NA_real_,
                      stringsAsFactors = FALSE))
  }
  v <- g$value[ok]; tr <- g$truth[1]
  cov_ok <- !is.na(g$lower) & !is.na(g$upper)
  cover <- mean(g$lower[cov_ok] <= tr & g$upper[cov_ok] >= tr)
  data.frame(
    cell = g$cell[1], arm = g$arm[1], estimate = g$estimate[1], truth = tr,
    n_run = nrow(g), n_used = n_used,
    bias = mean(v) - tr, bias_mcse = mcse_mean(v),
    rel_bias = 100 * (mean(v) - tr) / tr,
    rmse = sqrt(mean((v - tr)^2)),
    coverage = cover, coverage_mcse = mcse_prop(cover, sum(cov_ok)),
    width = mean(g$upper[cov_ok] - g$lower[cov_ok]),
    stringsAsFactors = FALSE)
}))
metrics <- merge(metrics, cl_tab[, c("cell", "delta", "top_factor", "R",
                                     "cv_control", "disp")], by = "cell")
metrics <- metrics[order(metrics$estimate, metrics$cell, metrics$arm), ]

dir.create(dirname(outfile), showWarnings = FALSE, recursive = TRUE)
utils::write.csv(metrics, outfile, row.names = FALSE)
cat("wrote", outfile, "with", nrow(metrics), "rows\n")
cat("iterations per cell/arm:\n")
print(table(metrics$cell, metrics$n_used))
