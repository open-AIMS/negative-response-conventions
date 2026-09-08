## Generating model for the simulation study.
##
## Copied verbatim from open-AIMS/negative-sgr at commit 0181d66e, R/simulate.R,
## so that the truth these datasets are drawn from is demonstrably the same one
## the earlier study used. Nothing here is new work; see REDESIGN-claude.md for
## what did change and why. Do not edit without re-recording the provenance.

## Simulation truth, designs and data generation (Phase 5).
##
## The generating model is the same `nec4param` the arms fit, on the raw SGR
## scale, with a genuinely negative lower asymptote. Everything is parameterised
## in the quantities the study argues about -- `R` (the control fold-change) and
## `Delta` (the discarded effect fraction) -- rather than in raw curve
## coefficients, so that a simulation cell and a real dataset can be compared
## directly.

#' The nec4param mean function, matching bayesnec's exactly
#'
#' `beta` is on the log scale: bayesnec writes `exp(beta)` inside the
#' exponential, so a `beta` of 0 is a decay rate of 1 per concentration unit.
nec4param_curve <- function(x, top, bot, beta, nec) {
  bot + (top - bot) * exp(-exp(beta) * (x - nec) * (x >= nec))
}

#' Build a truth from the study's own parameters
#'
#' @param R Control fold-change over the test. Sets `mu_0 = log(R)/t`, so `R`
#'   and `Delta` vary independently -- which the four real datasets cannot do,
#'   and which is the reason the simulation exists.
#' @param delta Discarded effect fraction `|bot|/mu_0`.
#' @param t Test duration in days.
#' @param nec True no-effect concentration.
#' @param beta Log decay rate.
## Defaults are the arm-A posterior means on c_proliferum, not hand-picked
## values: nec = 1.30, beta = -3.573 (a decay rate of 0.028 per ug/L),
## top = 0.130, delta = 7.97. Reproducing them recovers that dataset's
## endpoints -- ErC50 3.34 against the fitted 3.36, zero crossing 5.51 against
## 5.65.
##
## Getting this wrong is not a detail. An earlier pilot used nec = 5 with
## beta = log(0.4), which put the whole transition from control to zero growth
## inside 0.6 concentration units -- a near-step function no design can resolve
## and on which every arm would fail identically. Calibrating the SHAPE, not
## just the asymptotes, is what makes the arms distinguishable at all.
sim_truth <- function(R = 2.3, delta = 7.97, t = 7, nec = 1.3, beta = -3.573) {
  mu_0 <- log(R) / t
  bot <- -delta * mu_0
  b <- exp(beta)
  list(
    R = R, delta = delta, t = t, mu_0 = mu_0,
    top = mu_0, bot = bot, beta = beta, nec = nec,
    # Where the true curve crosses zero growth. bot + (top-bot)e^{-b(x-nec)} = 0
    # gives x = nec + log((top-bot)/(-bot))/b, and with bot = -delta*top the
    # ratio collapses to (1+delta)/delta -- so the crossing depends on delta and
    # the decay rate only, not on the growth rate itself.
    zero_crossing = nec + log((1 + delta) / delta) / b
  )
}

#' Analytic ErCx of the true curve
#'
#' `ecx(type = "absolute")` is the decline from `top` to zero, so ErCx solves
#' `curve(x) = top * (1 - p)`. Always defined here because `bot < 0 < top`.
true_ecx <- function(truth, ecx_val) {
  p <- ecx_val / 100
  target <- truth$top * (1 - p)
  truth$nec + log((truth$top - truth$bot) / (target - truth$bot)) /
    exp(truth$beta)
}

#' The concentration series
#'
#' Geometric, matching the real designs, with the top concentration placed
#' relative to the true zero-crossing -- the first simulation factor. A control
#' at x = 0 is added with its own replication.
sim_design <- function(truth, top_factor = 1, n_conc = 12, n_rep = 5,
                       n_control = 10, span = 100) {
  x_max <- top_factor * truth$zero_crossing
  x_min <- x_max / span
  concs <- exp(seq(log(x_min), log(x_max), length.out = n_conc))
  data.frame(
    x = c(rep(0, n_control), rep(concs, each = n_rep)),
    stringsAsFactors = FALSE
  )
}

#' Residual scale as a function of concentration
#'
#' Homoscedastic, or rising linearly with the fraction of the curve's range
#' already lost. `sigma_ratio` is the residual SD at the lower asymptote divided
#' by the residual SD at the control; it is calibrated from the real data by
#' `calibrate_sigma()` rather than assumed.
#'
#' Note that `bnec()` has no route to a distributional sigma (bayesnec issue
#' #191), so the heteroscedastic cells are *generated* heteroscedastic and
#' *fitted* homoscedastic. That is the realistic case, and it is described in
#' the results as misspecification rather than as a fitting option.
#' @param sigma_mode How the control residual SD is set.
#'   `"cv"` holds the *coefficient of variation* of the growth rate fixed, so
#'   `sigma_0 = cv_control * top`. `"absolute"` holds `sigma_0` itself fixed at
#'   `sigma_0_abs`, independent of the growth rate.
#' @param sigma_0_abs Control residual SD for `sigma_mode = "absolute"`. Anchor
#'   it with `sigma_0_at()` so that the reference cell is unchanged.
##
## Why the mode matters, and why "absolute" is the physically right default for
## any cell that varies R.
##
## Under "cv" the generating model is EXACTLY equivariant under rescaling the
## growth rate. top, bot and sigma are all proportional to mu_0 = log(R)/t,
## while nec, beta and the design do not involve R at all, so changing R
## multiplies every simulated response by a constant and leaves the x-axis
## untouched. Since ErCx, NSEC and the zero crossing are all x-axis quantities,
## and since flooring (max(y,0)), censoring (y <= 0) and a bot fixed at 0 are
## all scale-equivariant too, EVERY arm returns the same answer at every R.
## Verified numerically: with a common seed, y(R=73) = 5.1512 * y(R=2.3) to
## 3e-16, with identical rows floored and identical f_neg.
##
## So R is not an axis under "cv" -- which is a result in itself, and explains
## why Phase 3's R-ordering prediction failed on the real data. It was not
## underpowered at n = 4; it was structurally impossible.
##
## The equivariance is an artefact of tying sigma to mu_0. It is not the physics.
## Counting error lives on the log-density scale: with SD s on ln N at each time
## point, SGR = (ln N_t - ln N_0)/t has SD ~ s*sqrt(2)/t, which does not depend
## on the growth rate. Two tests with the same counting precision and different
## control growth rates have the same absolute SGR noise and different signal.
## Holding sigma_0 fixed is therefore what lets R enter at all, and it enters
## the way it should -- as signal-to-noise, which is also what OECD TG 201's
## R >= 16 validity criterion is implicitly buying.
sim_sigma <- function(x, truth, cv_control = 0.096, sigma_ratio = 1,
                      sigma_mode = c("cv", "absolute"), sigma_0_abs = NULL) {
  sigma_mode <- match.arg(sigma_mode)
  sigma_0 <- if (identical(sigma_mode, "absolute")) {
    if (is.null(sigma_0_abs)) stop("sigma_mode = 'absolute' needs sigma_0_abs.")
    sigma_0_abs
  } else {
    cv_control * truth$top
  }
  mu <- nec4param_curve(x, truth$top, truth$bot, truth$beta, truth$nec)
  lost <- (truth$top - mu) / (truth$top - truth$bot)
  sigma_0 * (1 + (sigma_ratio - 1) * lost)
}

#' The absolute control SD implied by a CV at a reference growth rate
#'
#' Anchors `sigma_mode = "absolute"` so that the reference cell is numerically
#' identical to the "cv" cell it replaces, and only the cells that move away
#' from `R_ref` change. Keeps the 9 core cells bit-comparable with the pilot.
sigma_0_at <- function(cv_control, R_ref = 2.3, t = 7) {
  cv_control * log(R_ref) / t
}

#' Generate one simulated dataset
#'
#' The returned frame carries a `density` column back-calculated from the
#' simulated growth rate, purely so that `prepare_sgr()` and `fit_arm()` can be
#' reused unchanged -- the simulation has no detection limit, so no row is ever
#' undefined and `raw`, `bound` and `supplied` coincide.
simulate_dataset <- function(truth, design, cv_control = 0.096,
                             sigma_ratio = 1, n_0 = 8000, seed = NULL,
                             sigma_mode = c("cv", "absolute"),
                             sigma_0_abs = NULL) {
  sigma_mode <- match.arg(sigma_mode)
  if (!is.null(seed)) set.seed(seed)
  mu <- nec4param_curve(design$x, truth$top, truth$bot, truth$beta, truth$nec)
  sg <- sim_sigma(design$x, truth, cv_control, sigma_ratio,
                  sigma_mode = sigma_mode, sigma_0_abs = sigma_0_abs)
  y <- stats::rnorm(length(mu), mu, sg)
  data.frame(
    dataset = "sim",
    x = design$x,
    sgr = y,
    density = n_0 * exp(y * truth$t),
    stringsAsFactors = FALSE
  )
}

#' `dataset_meta()` equivalent for simulated data
sim_meta <- function() {
  data.frame(dataset = "sim", species = "simulated", lod = NA_real_,
             duration_nominal = NA_real_, stringsAsFactors = FALSE)
}

#' Calibrate the residual-scale ratio from a real dataset
#'
#' Returns the control CV and the ratio of the residual SD in the deepest
#' treatment to that in the control. Used to set the heteroscedastic cells from
#' data rather than from a guess.
calibrate_sigma <- function(dat) {
  gm <- tapply(dat$sgr, dat$x, mean)
  gs <- tapply(dat$sgr, dat$x, stats::sd)
  ctrl <- names(gm)[1]
  deepest <- names(which.min(gm))
  list(
    cv_control = unname(gs[ctrl] / gm[ctrl]),
    sd_control = unname(gs[ctrl]),
    sd_deepest = unname(gs[deepest]),
    sigma_ratio = unname(gs[deepest] / gs[ctrl]),
    deepest_at = as.numeric(deepest)
  )
}

#' The estimands, computed the same way the estimator computes them
#'
#' ErC10 and ErC50 are analytic. NSEC's target is the true `nec`: NSEC is
#' defined against the *posterior* spread of the control response, so it has no
#' fixed value under a truth -- as the design grows it converges on the
#' threshold itself. Fisher and Fox (2023) present NSEC as an alternative
#' estimator of a no-effect concentration, so `nec` is the right target, with
#' the caveat that any bias it shows includes a design component shared by every
#' arm. The arm-to-arm contrast, not the absolute bias, is the quantity of
#' interest for NSEC.
true_endpoints <- function(truth) {
  data.frame(
    endpoint = c("ErC10", "ErC50", "NSEC"),
    truth = c(true_ecx(truth, 10), true_ecx(truth, 50), truth$nec),
    stringsAsFactors = FALSE
  )
}

#' Does the design actually resolve the transition?
#'
#' Counts how many tested concentrations fall between ErC10 and the zero
#' crossing. Fewer than about three and the arms cannot differ for any reason
#' this study is about: as far as the design is concerned the curve is a step.
#' That is r_salina's problem, not c_proliferum's, and it must not be built into
#' the simulation by accident.
resolves_transition <- function(truth, design) {
  x <- sort(unique(design$x[design$x > 0]))
  lo <- true_ecx(truth, 10)
  n_in <- sum(x >= lo & x <= truth$zero_crossing)
  list(n_in_transition = n_in, ercx10 = lo, ercx50 = true_ecx(truth, 50),
       zero_crossing = truth$zero_crossing, adequate = n_in >= 3)
}

#' Check the analytic ErCx against the package's grid estimator
#'
#' Guards against the simulation measuring discretisation rather than bias: if
#' the analytic value and the grid value disagree by more than the grid spacing,
#' the metric is comparing two different things.
check_ecx_estimator <- function(truth, resolution = 1000, span = 100) {
  x_max <- 2 * truth$zero_crossing
  x_seq <- seq(0, x_max, length.out = resolution)
  y <- nec4param_curve(x_seq, truth$top, truth$bot, truth$beta, truth$nec)
  grid_ecx <- function(p) {
    target <- max(y) * (1 - p / 100)
    x_seq[which.min(abs(y - target))]
  }
  data.frame(
    endpoint = c("ErC10", "ErC50"),
    analytic = c(true_ecx(truth, 10), true_ecx(truth, 50)),
    grid = c(grid_ecx(10), grid_ecx(50)),
    grid_spacing = diff(x_seq[1:2])
  )
}
