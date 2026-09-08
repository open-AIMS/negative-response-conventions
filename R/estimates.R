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
    weights = I(list(w)),
    stringsAsFactors = FALSE
  )
}

#' Everything one (cell, iteration, arm) contributes
#'
#' Written to its own file by the runner, so the run is resumable by existence
#' check and a lost block costs only the block.
run_one <- function(cl, iteration, arm) {
  dat <- cell_dataset(cl, iteration)
  res <- fit_arm(dat, arm, seed = 333L + iteration, disp = cl$disp)
  rec <- res$record
  out <- list(cell = cl$cell, iteration = iteration, arm = arm,
              record = rec, estimates = NULL, weights = NULL)
  if (is.null(res$fit)) return(out)
  out$estimates <- arm_estimates(res$fit)
  out$weights <- try(arm_weights(res$fit), silent = TRUE)
  if (inherits(out$weights, "try-error")) out$weights <- NULL
  out
}
