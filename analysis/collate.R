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
## Only when it exists: a stale lib/ shadows whatever library this is run
## against, silently. See hpc/README.md.
if (dir.exists(file.path(ROOT, "lib"))) {
  .libPaths(c(file.path(ROOT, "lib"), .libPaths()))
}
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

args <- commandArgs(trailingOnly = TRUE)
outfile <- if (length(args)) args[1] else file.path(ROOT, "results", "metrics.csv")

files <- list.files(file.path(ROOT, "results"), "^iter_\\d+\\.rds$",
                    recursive = TRUE, full.names = TRUE)
## Not an error when the simulation has not produced anything yet: the 24 case
## units finish long before the 4,200 simulation units, and the vignette needs
## them first, so this has to be runnable on whichever half exists.
have_sim <- length(files) > 0
if (have_sim) {
  cat("collating", length(files), "simulation result files\n")
} else {
  cat("no simulation results under results/ yet; case studies only\n")
}

if (have_sim) {
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

  ## Model weights and per-equation diagnostics, collated beside the estimates
  ## rather than only summarised into them. The previous run recorded neither, so
  ## when the question "does a badly mixing equation carry any weight" was asked
  ## there was nothing on disk to answer it with.
  weight_rows <- lapply(files, function(f) {
    o <- readRDS(f)
    if (is.null(o$weights)) return(NULL)
    data.frame(cell = o$cell, arm = o$arm, iteration = o$iteration,
               n_models = o$weights$n_models,
               top_model = o$weights$top_model,
               top_weight = o$weights$top_weight,
               w_nec4param = o$weights$w_nec4param,
               w_zero_asymptote = o$weights$w_zero_asymptote,
               stringsAsFactors = FALSE)
  })
  weights_tab <- do.call(rbind, weight_rows)

  diag_rows <- lapply(files, function(f) {
    o <- readRDS(f)
    if (is.null(o$diagnostics)) return(NULL)
    cbind(data.frame(cell = o$cell, arm = o$arm, iteration = o$iteration,
                     stringsAsFactors = FALSE), o$diagnostics)
  })
  diag_tab <- do.call(rbind, diag_rows)

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

  if (!is.null(weights_tab)) {
    wf <- file.path(dirname(outfile), "weights.csv")
    utils::write.csv(weights_tab, wf, row.names = FALSE)
    cat("wrote", wf, "with", nrow(weights_tab), "rows\n")
  }
  if (!is.null(diag_tab)) {
    df <- file.path(dirname(outfile), "diagnostics.csv")
    utils::write.csv(diag_tab, df, row.names = FALSE)
    cat("wrote", df, "with", nrow(diag_tab), "rows\n")
    ## The only reading of a diagnostic that means anything: how much stacking
    ## weight sits on equations that failed one. An equation whose shape suits the
    ## data badly fails whatever the data are doing and is given almost no weight
    ## for the same reason.
    bad <- stats::aggregate(
      cbind(w_rhat = weight * (max_rhat > 1.01),
            w_ess = weight * (min_ess_tail < 400)) ~ cell + arm,
      data = diag_tab, FUN = mean)
    cat("\nmean weight held by equations failing a diagnostic:\n")
    print(bad[order(-bad$w_rhat - bad$w_ess), ][seq_len(min(10, nrow(bad))), ],
          row.names = FALSE, digits = 3)
  }
}

## The dispersion sweep, scored against the same truth as the study, so the two
## tables stack. Kept in its own file rather than merged: these arms exist on
## four cells only, and a metrics table with empty rows for the other three
## invites the two to be read as one design.
disp_files <- list.files(file.path(ROOT, "results_disp"), "^iter_\\d+\\.rds$",
                         recursive = TRUE, full.names = TRUE)
if (length(disp_files)) {
  cat("\ncollating", length(disp_files), "dispersion-sweep files\n")
  draw <- do.call(rbind, lapply(disp_files, function(f) {
    o <- readRDS(f)
    if (is.null(o$estimates)) return(NULL)
    cbind(data.frame(cell = o$cell, arm = o$arm, iteration = o$iteration,
                     stringsAsFactors = FALSE), o$estimates)
  }))
  truth_d <- do.call(rbind, lapply(disp_cells(), function(cc) {
    tv <- cell_truth(cells()[cells()$cell == cc, ])$true_values
    data.frame(cell = cc, estimate = names(tv), truth = unname(tv),
               stringsAsFactors = FALSE)
  }))
  draw <- merge(draw, truth_d, by = c("cell", "estimate"), all.x = TRUE)
  md <- do.call(rbind, lapply(split(draw, list(draw$cell, draw$arm, draw$estimate),
                                    drop = TRUE), function(g) {
    ok <- !is.na(g$value); v <- g$value[ok]; tr <- g$truth[1]
    cov_ok <- !is.na(g$lower) & !is.na(g$upper)
    cover <- mean(g$lower[cov_ok] <= tr & g$upper[cov_ok] >= tr)
    data.frame(cell = g$cell[1], arm = g$arm[1], estimate = g$estimate[1],
               truth = tr, n_run = nrow(g), n_used = sum(ok),
               rel_bias = 100 * (mean(v) - tr) / tr,
               rmse = sqrt(mean((v - tr)^2)),
               coverage = cover, width = mean(g$upper[cov_ok] - g$lower[cov_ok]),
               stringsAsFactors = FALSE)
  }))
  md <- merge(md, cells()[, c("cell", "cv_control")], by = "cell")
  md <- md[order(md$estimate, md$cell, md$arm), ]
  mdf <- file.path(dirname(outfile), "metrics_disp.csv")
  utils::write.csv(md, mdf, row.names = FALSE)
  cat("wrote", mdf, "with", nrow(md), "rows\n")
  dd <- do.call(rbind, lapply(disp_files, function(f) {
    o <- readRDS(f)
    if (is.null(o$diagnostics)) return(NULL)
    cbind(data.frame(cell = o$cell, arm = o$arm, iteration = o$iteration,
                     stringsAsFactors = FALSE), o$diagnostics)
  }))
  if (!is.null(dd)) {
    utils::write.csv(dd, file.path(dirname(outfile), "diagnostics_disp.csv"),
                     row.names = FALSE)
    cat("wrote diagnostics_disp.csv with", nrow(dd), "rows\n")
  }
}

## The case studies, collated the same way but against no truth: there is none.
case_files <- list.files(file.path(ROOT, "results_cases"), "\\.rds$",
                         recursive = TRUE, full.names = TRUE)
if (length(case_files)) {
  cat("\ncollating", length(case_files), "case-study files\n")
  ce <- do.call(rbind, lapply(case_files, function(f) {
    o <- readRDS(f)
    if (is.null(o$estimates)) return(NULL)
    cbind(data.frame(dataset = o$dataset, arm = o$arm,
                     x_min = o$x_range[1], x_max = o$x_range[2],
                     n_negative = o$n_negative,
                     w_nec4param = if (is.null(o$weights)) NA_real_ else o$weights$w_nec4param,
                     w_zero_asymptote = if (is.null(o$weights)) NA_real_ else o$weights$w_zero_asymptote,
                     top_model = if (is.null(o$weights)) NA_character_ else o$weights$top_model,
                     top_weight = if (is.null(o$weights)) NA_real_ else o$weights$top_weight,
                     w_failing_rhat = if (is.null(o$diagnostics)) NA_real_ else
                       sum(o$diagnostics$weight[o$diagnostics$max_rhat > 1.01]),
                     w_failing_ess = if (is.null(o$diagnostics)) NA_real_ else
                       sum(o$diagnostics$weight[o$diagnostics$min_ess_tail < 400]),
                     stringsAsFactors = FALSE),
          o$estimates)
  }))
  cf <- file.path(dirname(outfile), "case_estimates.csv")
  utils::write.csv(ce, cf, row.names = FALSE)
  cat("wrote", cf, "with", nrow(ce), "rows\n")
  cd <- do.call(rbind, lapply(case_files, function(f) {
    o <- readRDS(f)
    if (is.null(o$diagnostics)) return(NULL)
    cbind(data.frame(dataset = o$dataset, arm = o$arm, stringsAsFactors = FALSE),
          o$diagnostics)
  }))
  if (!is.null(cd)) {
    cdf <- file.path(dirname(outfile), "case_diagnostics.csv")
    utils::write.csv(cd, cdf, row.names = FALSE)
    cat("wrote", cdf, "with", nrow(cd), "rows\n")
  }
}
