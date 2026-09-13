## Predicted against observed residual spread, by dose group.
##
## The simulation generates a residual standard deviation that is constant along
## the curve, so the target is known exactly: a correctly specified variance
## model predicts that value at every concentration, giving a ratio of one to
## the generated value and a ratio of one between the top and the bottom of the
## curve. What a family gets wrong is then readable as a departure from one in
## either direction.
##
## This is recorded per unit rather than computed afterwards from saved fits.
## Saving 2,000 fitted objects is 22GB; the statistic is two numbers and
## `posterior_predict()` on a model-averaged fit takes about two seconds, which
## is nothing against the minutes the fit itself takes. Computing it from one
## saved exemplar per cell, which is what was done first, gives a single
## realisation and no way to tell a difference from realisation noise.

#' Model-averaged predicted spread by dose group
#'
#' @param fit A fitted object from `bnec()`.
#' @param scale Multiplier putting the predicted spread back on the response
#'   scale. The Beta arms are fitted to the response divided by its maximum, so
#'   their predicted spread is on the (0, 1] scale; without this the comparison
#'   overstates it by the scaling factor.
#' @param ndraws Posterior predictive draws.
#'
#' @return One row per dose group with at least four observations: the group's
#'   predictor value, its mean response, the observed standard deviation and the
#'   model-averaged predicted one.
ppc_spread <- function(fit, scale = 1, ndraws = 400) {
  if (!requireNamespace("brms", quietly = TRUE)) return(NULL)
  bf <- if (inherits(fit, "bayesmanecfit")) fit$mod_fits[[1]]$fit else fit$fit
  y <- bf$data[[1]]
  # The predictor by name: for a censored model it is not the second column,
  # which is the censoring indicator.
  xn <- if ("x" %in% names(bf$data)) "x" else names(bf$data)[ncol(bf$data)]
  x <- bf$data[[xn]]
  # The model-averaged predictive, not the highest-weighted equation's: the
  # estimates this is read against are model-averaged, so the diagnostic must be.
  yr <- try(brms::posterior_predict(fit, ndraws = ndraws), silent = TRUE)
  if (inherits(yr, "try-error")) return(NULL)
  g <- split(seq_along(y), x)
  g <- g[vapply(g, length, integer(1)) >= 4L]
  if (!length(g)) return(NULL)
  do.call(rbind, lapply(names(g), function(nm) {
    i <- g[[nm]]
    data.frame(x = as.numeric(nm), mu = mean(y[i]) * scale,
               sd_obs = stats::sd(y[i]) * scale,
               sd_pred = mean(apply(yr[, i, drop = FALSE], 1, stats::sd)) * scale,
               n = length(i), stringsAsFactors = FALSE)
  }))
}

#' The scaling an arm applied to the response, so `ppc_spread()` can undo it
ppc_scale <- function(dat, arm) {
  base <- sub("_(ll|pw)$", "", arm)
  if (identical(base, "beta")) max(pmax(dat$sgr, 0)) else 1
}
