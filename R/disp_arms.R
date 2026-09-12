## The dispersion arms: the same conventions, refitted with the family's
## dispersion parameter allowed to vary along the curve.
##
## They are kept separate from arm_names() rather than added to it. The study's
## unit queue is built by crossing cells with arm_names(), so extending that
## would renumber every array index of a completed run; and the question these
## answer is narrower than the study's, so they run on the precision cells only.
##
## The question. An analyst holding data that have already been floored, and
## cannot un-floor them, reaches for a bounded family. A posterior predictive
## check on the p1 exemplars showed what that does: against a residual SD
## generated constant at 0.0114, an identity-link Gamma predicts 3.5 times too
## much spread at the control, too little at the shoulder and none at all at the
## floored values -- because it ties the dispersion to the mean. A dispersion
## sub-model unties them. Whether that repairs the estimates is what these
## measure.
##
## `floored_ll` is the control. The same check found the Gaussian conventions
## already describe the spread correctly, so a dispersion sub-model should buy
## nothing there, and showing that is worth as much as showing where it helps.

#' The dispersion arms, their base convention and the sub-model each uses
disp_arms <- function() {
  data.frame(
    arm      = c("floored_ll", "gamma_ll",  "gamma_pw", "beta_ll",   "beta_pw"),
    base_arm = c("floored",    "gamma",     "gamma",    "beta",      "beta"),
    disp     = c("loglinear",  "loglinear", "power",    "loglinear", "power"),
    stringsAsFactors = FALSE)
}

#' The cells these run on: the precision sweep only
#'
#' The sweep is what separates estimation error from misspecification, and it is
#' the axis on which the bounded families fail -- their bias grows as the
#' experiment improves. The cells that vary the depth of the decline or stop the
#' series short answer a different question and are not re-run here.
disp_cells <- function() c("p1", "p2", "p3", "p4")

#' The queue of dispersion-sweep units, in a fixed order
disp_queue <- function(n_iter = 100L, arms = disp_arms()$arm) {
  cl <- disp_cells()
  do.call(rbind, lapply(seq_len(n_iter), function(it) {
    do.call(rbind, lapply(cl, function(c) {
      data.frame(cell = c, arm = arms, iteration = it, stringsAsFactors = FALSE)
    }))
  }))
}

#' Everything one dispersion-sweep unit contributes
#'
#' The same record as a study unit, so the two collate together.
run_disp_unit <- function(cell, arm, iteration, prior_dir = "priors_disp") {
  spec <- disp_arms()[disp_arms()$arm == arm, ]
  if (!nrow(spec)) stop("unknown dispersion arm ", arm)
  cl <- cells()[cells()$cell == cell, ]
  dat <- cell_dataset(cl, iteration)
  pr <- prior_for(cell, arm, prior_dir)
  res <- fit_arm(dat, spec$base_arm, seed = 333L + iteration, disp = spec$disp,
                 prior = pr)
  out <- list(cell = cell, iteration = iteration, arm = arm,
              record = res$record, estimates = NULL, weights = NULL,
              diagnostics = NULL)
  if (is.null(res$fit)) return(out)
  out$estimates <- arm_estimates(res$fit)
  out$weights <- try(arm_weights(res$fit), silent = TRUE)
  if (inherits(out$weights, "try-error")) out$weights <- NULL
  out$diagnostics <- try(arm_diagnostics(res$fit), silent = TRUE)
  if (inherits(out$diagnostics, "try-error")) out$diagnostics <- NULL
  out
}
