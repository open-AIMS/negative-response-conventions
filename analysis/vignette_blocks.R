## Regenerate the transcribed CSV blocks in bayesnec's example7.Rmd.orig.
##
##   Rscript analysis/vignette_blocks.R <path to example7.Rmd.orig>
##
## The vignette transcribes its figures rather than reading these tables,
## because a package vignette cannot depend on this compendium being present.
## Regenerating them with a script rather than by hand is what stops a re-run of
## the study leaving the text describing an earlier one. Validate a change to
## this file by running it against the tables of the run the vignette currently
## reports: it must reproduce the committed blocks byte for byte.

ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) stop("run from the compendium root")
rmd <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(rmd) || !file.exists(rmd)) stop("give the path to example7.Rmd.orig")

arms  <- c("measured", "censored", "deleted", "floored", "beta", "gamma")
cells <- c("p1", "p2", "p3", "p4", "d2", "d8", "ctl")
ests  <- c("ErC10", "ErC50", "NSEC")

## as.character(round()) rather than format(): the blocks drop trailing zeros
## ("0.9", not "0.90"), and keeping that makes a diff show only figures that
## actually changed.
num <- function(x, d) as.character(round(x, d))

ord <- function(d, keys) {
  d$.cell <- factor(d$cell, levels = cells)
  d$.arm  <- factor(d$arm, levels = arms)
  if ("estimate" %in% names(d)) {
    d$.est <- factor(d$estimate, levels = ests)
    d <- d[order(d$.est, d$.cell, d$.arm), ]
  } else {
    d <- d[order(d$.cell, d$.arm), ]
  }
  d[, keys, drop = FALSE]
}

## ---- the simulation metrics ------------------------------------------------
m <- read.csv(file.path(ROOT, "results", "metrics.csv"))
sim <- data.frame(
  cell = m$cell, arm = m$arm, estimate = m$estimate,
  ## Three decimals, not two: the vignette rounds this again with f1(), and a
  ## value stored at 2 dp that lands on a .x5 boundary then rounds the wrong
  ## way -- a raw -0.4455 stored as -0.45 was reported as "-0.5", not "-0.4".
  rel_bias = num(m$rel_bias, 3),
  coverage = num(m$coverage, 2),
  width    = num(m$width, 4),
  rmse     = num(m$rmse, 4),
  ## Monte Carlo standard error of the bias as a percentage of the truth, so it
  ## is on the same scale as rel_bias and a reader can see which differences the
  ## 100 realisations resolve.
  mcse_pct = num(100 * m$bias_mcse / m$truth, 3)
)
sim <- ord(sim, c("cell", "arm", "estimate", "rel_bias", "coverage",
                  "width", "rmse", "mcse_pct"))

## ---- the model weights -----------------------------------------------------
w <- read.csv(file.path(ROOT, "results", "weights.csv"))
ws <- aggregate(cbind(w_nec4param, w_zero_asymptote, n_models) ~ cell + arm,
                data = w, FUN = mean)
## `top_model` is the equation most often given the highest weight across the
## realisations, and `top_weight` the mean weight held by whichever equation won
## each time. Not the equation with the highest mean weight: averaging first
## reports a weight no single realisation gave, and in p1/censored the two
## definitions name different equations.
tw <- do.call(rbind, lapply(split(w, list(w$cell, w$arm), drop = TRUE),
  function(d) data.frame(
    cell = d$cell[1], arm = d$arm[1],
    top_model = names(sort(table(d$top_model), decreasing = TRUE))[1],
    top_weight = mean(d$top_weight))))
ws <- merge(ws, tw, by = c("cell", "arm"))
weights <- data.frame(
  cell = ws$cell, arm = ws$arm,
  w_nec4param      = num(ws$w_nec4param, 3),
  w_zero_asymptote = num(ws$w_zero_asymptote, 3),
  n_models         = num(ws$n_models, 1),
  top_model        = ws$top_model,
  top_weight       = num(ws$top_weight, 3)
)
weights <- ord(weights, c("cell", "arm", "w_nec4param", "w_zero_asymptote",
                          "n_models", "top_model", "top_weight"))

## ---- the case studies ------------------------------------------------------
ce <- read.csv(file.path(ROOT, "results", "case_estimates.csv"))
dsl <- c("c_proliferum", "c_proliferum2", "r_salina", "r_salina2")
ce$.ds  <- factor(ce$dataset, levels = dsl)
ce$.arm <- factor(ce$arm, levels = arms)
ce$.est <- factor(ce$estimate, levels = ests)
ce <- ce[order(ce$.ds, ce$.arm, ce$.est), ]
cases <- data.frame(
  dataset = ce$dataset, arm = ce$arm, estimate = ce$estimate,
  value = num(ce$value, 4), lower = num(ce$lower, 4), upper = num(ce$upper, 4),
  x_min = num(ce$x_min, 4), x_max = num(ce$x_max, 4),
  w_zero_asymptote = num(ce$w_zero_asymptote, 3),
  w_failing_ess    = num(ce$w_failing_ess, 3)
)

## ---- splice ----------------------------------------------------------------
to_lines <- function(d) c(paste(names(d), collapse = ","),
                          apply(d, 1, paste, collapse = ","))

lines <- readLines(rmd)
replace_block <- function(lines, object, body) {
  start <- grep(paste0("^", object, " <- read\\.csv\\(text = \"$"), lines)
  if (length(start) != 1) stop("could not find one ", object, " block")
  end <- start + which(lines[(start + 1):length(lines)] == "\")")[1]
  c(lines[seq_len(start - 1)], lines[start], body, "\")",
    lines[(end + 1):length(lines)])
}
lines <- replace_block(lines, "sim", to_lines(sim))
lines <- replace_block(lines, "weights", to_lines(weights))
lines <- replace_block(lines, "cases", to_lines(cases))
writeLines(lines, rmd)
cat("spliced:", nrow(sim), "sim rows,", nrow(weights), "weight rows,",
    nrow(cases), "case rows\n")
