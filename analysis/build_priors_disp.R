## Fixed priors for the dispersion arms, one per cell and arm, from the same
## reference realisation the study uses. No model is fitted.
##
## Needed for the same reason the study's are: bayesnec derives its defaults
## from the response and brms writes them into the Stan source as literals, so a
## prior that varies by realisation makes every fit a distinct program. With a
## dispersion sub-model there are more parameters to vary, not fewer.

ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) stop("run from the compendium root")
if (dir.exists(file.path(ROOT, "lib"))) {
  .libPaths(c(file.path(ROOT, "lib"), .libPaths()))
}
suppressMessages(library(bayesnec))
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

dir.create(file.path(ROOT, "priors_disp"), showWarnings = FALSE)
spec <- disp_arms()
n <- 0L
for (cell in disp_cells()) {
  cl <- cells()[cells()$cell == cell, ]
  d0 <- cell_dataset(cl, 0L)
  for (i in seq_len(nrow(spec))) {
    p <- prepare_arm(d0, spec$base_arm[i])
    f <- stats::update(p$formula,
                       stats::as.formula(sprintf(". ~ . + disp(\"%s\")",
                                                 spec$disp[i])))
    pr <- try(get_priors(bnf(f), data = p$data, family = p$family), silent = TRUE)
    if (inherits(pr, "try-error")) {
      cat(sprintf("%-4s %-11s REFUSED: %s\n", cell, spec$arm[i],
                  sub("\n.*", "", conditionMessage(attr(pr, "condition")))))
      next
    }
    saveRDS(pr, file.path(ROOT, "priors_disp",
                          sprintf("%s__%s.rds", cell, spec$arm[i])))
    cat(sprintf("%-4s %-11s %d equations\n", cell, spec$arm[i], length(pr)))
    n <- n + 1L
  }
}
cat("\n", n, "priors written to priors_disp/\n")
