## Pulling the three toxicity estimates off a model-averaged fit, and the
## per-iteration record that the metrics are aggregated from.

ESTIMATES <- c("ErC10", "ErC50", "NSEC")

#' The three estimates, with their 95% credible intervals, from one fit
#'
#' Returns one row per estimate. A value that could not be identified comes back
#' NA rather than being dropped, so that the metrics can report how often each
#' arm failed to produce an answer -- which is itself a result, and was one of
#' the more useful findings of the previous study.
arm_estimates <- function(fit) {
  grab <- function(f, label) {
    v <- try(suppressWarnings(f()), silent = TRUE)
    if (inherits(v, "try-error") || length(v) < 3 || !is.finite(v[1])) {
      return(data.frame(estimate = label, value = NA_real_, lower = NA_real_,
                        upper = NA_real_, stringsAsFactors = FALSE))
    }
    data.frame(estimate = label, value = as.numeric(v[1]),
               lower = as.numeric(v[2]), upper = as.numeric(v[3]),
               stringsAsFactors = FALSE)
  }
  rbind(
    grab(function() bayesnec::ecx(fit, ecx_val = 10, type = "absolute"), "ErC10"),
    grab(function() bayesnec::ecx(fit, ecx_val = 50, type = "absolute"), "ErC50"),
    grab(function() bayesnec::nsec(fit), "NSEC")
  )
}

#' Mean model weight per equation, and how many equations survived
#'
#' The weights answer question 5: which shape each convention makes the data
#' look like. `nec4param` is named separately because it is the generating
#' equation, so its weight measures how far each convention moves the data away
#' from the process that produced them.
arm_weights <- function(fit) {
  if (inherits(fit, "bayesmanecfit")) {
    w <- fit$mod_stats$wi
    names(w) <- rownames(fit$mod_stats)
  } else {
    w <- c(1)
    names(w) <- fit$model
  }
  data.frame(
    n_models = length(w),
    top_model = names(w)[which.max(w)],
    top_weight = unname(max(w)),
    w_nec4param = unname(if ("nec4param" %in% names(w)) w[["nec4param"]] else 0),
    # The six equations whose lower asymptote is fixed at zero. Their combined
    # weight is the signature of the substitution, and it identifies it only
    # where the substitution is what imposes the boundary: under a Beta or a
    # Gamma the family already forbids a negative mean, so an equation with a
    # free lower asymptote is bounded below in any case and these six are not
    # needed. Reported for every arm so that asymmetry is visible rather than
    # assumed.
    w_zero_asymptote = sum(w[names(w) %in% ZERO_ASYMPTOTE]),
    weights = I(list(w)),
    stringsAsFactors = FALSE
  )
}

## The equations that hold the lower asymptote at zero.
ZERO_ASYMPTOTE <- c("nec3param", "ecxexp", "ecxsigm", "ecxwb1p3", "ecxwb2p3",
                    "ecxll3")

#' Per-equation convergence diagnostics, with the weight each equation holds
#'
#' Reported together because that is the only way to read them: an equation
#' whose shape suits the data badly fails a diagnostic whatever the data are
#' doing, and is given almost no stacking weight for the same reason, so a
#' failure on a near-zero-weight equation says something about that curve and
#' nothing about the model-averaged estimates. Measured on one real dataset
#' during the rewrite, `nec3param` had a tail ESS of 148 and a weight of
#' 1.3e-15.
#'
#' Returns one row per equation. `max_rhat` and `min_ess_tail` are taken over
#' the curve parameters only -- `top`, `bot`, `nec`, `beta`, `ec50` -- because a
#' dispersion parameter mixing badly is a different problem from a curve that is
#' not identified.
arm_diagnostics <- function(fit) {
  if (!requireNamespace("posterior", quietly = TRUE)) {
    return(NULL)
  }
  fits <- if (inherits(fit, "bayesmanecfit")) fit$mod_fits else
    setNames(list(fit), fit$model)
  w <- if (inherits(fit, "bayesmanecfit")) {
    setNames(fit$mod_stats$wi, rownames(fit$mod_stats))
  } else {
    setNames(1, fit$model)
  }
  do.call(rbind, lapply(names(fits), function(m) {
    bf <- if (inherits(fit, "bayesmanecfit")) fits[[m]]$fit else fits[[m]]$fit
    d <- try(posterior::as_draws_df(bf), silent = TRUE)
    if (inherits(d, "try-error")) return(NULL)
    keep <- grep("^b_(top|bot|nec|beta|ec50)_", names(d))
    if (!length(keep)) return(NULL)
    s <- posterior::summarise_draws(d[, keep, drop = FALSE], "rhat", "ess_tail")
    data.frame(model = m,
               weight = unname(if (m %in% names(w)) w[[m]] else 0),
               max_rhat = max(s$rhat, na.rm = TRUE),
               min_ess_tail = min(s$ess_tail, na.rm = TRUE),
               stringsAsFactors = FALSE)
  }))
}

#' The fixed prior for one cell and arm
#'
#' Returns NULL if none has been built, in which case bnec() falls back to its
#' own defaults and the fit recompiles. That is a correct fit, just an expensive
#' one, so it warns rather than stops: a missing prior should not lose a unit.
prior_for <- function(cell, arm, prior_dir = "priors") {
  f <- file.path(prior_dir, sprintf("%s__%s.rds", cell, arm))
  if (!file.exists(f)) {
    warning("no fixed prior for ", cell, "/", arm, "; using bnec() defaults, ",
            "which will recompile every model", call. = FALSE)
    return(NULL)
  }
  readRDS(f)
}

#' Everything one (cell, iteration, arm) contributes
#'
#' Written to its own file by the runner, so the run is resumable by existence
#' check and a lost block costs only the block.
run_one <- function(cl, iteration, arm, prior_dir = "priors") {
  dat <- cell_dataset(cl, iteration)
  pr <- prior_for(cl$cell, arm, prior_dir)
  res <- fit_arm(dat, arm, seed = 333L + iteration, disp = cl$disp, prior = pr)
  rec <- res$record
  out <- list(cell = cl$cell, iteration = iteration, arm = arm,
              record = rec, estimates = NULL, weights = NULL,
              diagnostics = NULL)
  if (is.null(res$fit)) return(out)
  out$estimates <- arm_estimates(res$fit)
  out$weights <- try(arm_weights(res$fit), silent = TRUE)
  if (inherits(out$weights, "try-error")) out$weights <- NULL
  # Carried for the same reason the case studies carry it: a diagnostic is only
  # readable against the weight its equation holds, and the previous run of this
  # study recorded no diagnostics at all, so there was nothing to check when the
  # question was asked.
  out$diagnostics <- try(arm_diagnostics(res$fit), silent = TRUE)
  if (inherits(out$diagnostics, "try-error")) out$diagnostics <- NULL
  out
}
