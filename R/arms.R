## The six data-handling conventions under test.
##
## Every arm is what an analyst actually does: it prepares the data, then calls
## bnec() with package defaults -- default priors, the default declining model
## set for the family, default weighting. No arm is handed a prior built by
## another, so a contrast between arms is the contrast a practitioner would
## obtain, not a likelihood-only contrast. That is the question this study asks;
## see REDESIGN-claude.md section 3.

arm_names <- function() {
  c("measured", "floored", "deleted", "censored", "beta", "gamma")
}

#' One-line description of each arm, for figure keys and the report
arm_labels <- function() {
  c(measured = "use the values as recorded",
    floored  = "replace negatives with zero",
    deleted  = "delete the negative rows",
    censored = "declare negatives left-censored at zero",
    beta     = "floor, scale to (0, 1), fit a Beta",
    gamma    = "floor, fit a Gamma")
}

#' Prepare one dataset for one arm
#'
#' Returns a list with the data frame to fit, the bnec() formula, the family,
#' and a record of what the preparation changed. The record is the point of
#' separating this from the fitting: the report has to be able to say how many
#' rows each convention altered, and on which datasets an arm was not estimable.
prepare_arm <- function(dat, arm) {
  stopifnot(arm %in% arm_names())
  n_neg <- sum(dat$sgr < 0)
  rec <- list(arm = arm, n_rows_in = nrow(dat), n_negative = n_neg,
              n_altered = 0L, n_removed = 0L, n_conc_lost = 0L,
              estimable = TRUE, note = NA_character_)

  if (arm == "measured") {
    d <- transform(dat, y = sgr)
    form <- y ~ crf(x, "decline")
    fam <- gaussian(link = "identity")

  } else if (arm == "floored") {
    d <- transform(dat, y = pmax(sgr, 0))
    rec$n_altered <- n_neg
    form <- y ~ crf(x, "decline")
    fam <- gaussian(link = "identity")

  } else if (arm == "deleted") {
    # Deleting rows changes the replication per concentration, and at the top of
    # the series can remove a whole treatment group. That is the practice, but a
    # design with too few surviving concentrations cannot support the model set,
    # so it is refused here rather than allowed to fail obscurely downstream.
    keep <- dat$sgr >= 0
    d <- transform(dat[keep, , drop = FALSE], y = sgr)
    rec$n_removed <- sum(!keep)
    rec$n_conc_lost <- length(unique(dat$x)) - length(unique(d$x))
    if (length(unique(d$x)) < 4 || nrow(d) < 10) {
      rec$estimable <- FALSE
      rec$note <- sprintf("deletion left %d rows across %d concentrations",
                          nrow(d), length(unique(d$x)))
    }
    form <- y ~ crf(x, "decline")
    fam <- gaussian(link = "identity")

  } else if (arm == "censored") {
    # Left-censoring declares that the truth lies at or below a bound, so the
    # bound should be the tightest one the measurement supports. For a value
    # that was measured and came out negative that is zero: withdrawing the
    # magnitude is the convention under test. For a row that was never measured
    # -- a population below a counting limit -- it is the limit itself, which is
    # a stronger statement than "below zero" and is the one thing the test does
    # establish about that row.
    #
    # `cens_bound` and `below_limit` are optional and absent in the simulation,
    # where every row is measured and the bound is zero everywhere. Supplying
    # them is what lets the case studies run this same definition rather than a
    # second copy of it.
    b <- if ("cens_bound" %in% names(dat)) dat$cens_bound else rep(0, nrow(dat))
    bl <- if ("below_limit" %in% names(dat)) dat$below_limit else rep(FALSE, nrow(dat))
    left <- bl | dat$sgr < b
    d <- transform(dat, y = ifelse(left, b, sgr),
                   cens = ifelse(left, "left", "none"))
    rec$n_altered <- sum(left)
    form <- y | cens(cens) ~ crf(x, "decline")
    fam <- gaussian(link = "identity")

  } else if (arm == "beta") {
    # Floor first, then scale to (0, 1]. bnec() will shift the resulting exact
    # zeros to one tenth of the smallest positive value, because a Beta cannot
    # represent a zero. That shift is part of the convention under test and is
    # deliberately not pre-empted; check_data() reports it once per call.
    y <- pmax(dat$sgr, 0)
    d <- transform(dat, y = y / max(y))
    rec$n_altered <- n_neg
    form <- y ~ crf(x, "decline")
    fam <- Beta(link = "identity")

  } else {
    d <- transform(dat, y = pmax(sgr, 0))
    rec$n_altered <- n_neg
    form <- y ~ crf(x, "decline")
    fam <- Gamma(link = "identity")
  }

  list(data = d, formula = form, family = fam, record = rec)
}

#' Fit one arm to one dataset, model-averaged over the family's declining set
#'
#' `iter`, `warmup`, `adapt_delta` and `max_treedepth` match the previous
#' study's `MCMC` list so the two are comparable on sampling effort.
#'
#' `backend = "cmdstanr"` is not optional. brms defaults to rstan, which
#' recompiles every model in every session and made a single arm exceed ten
#' minutes here without producing a fit. cmdstanr writes each program to
#' `cmdstanr_write_stan_file_dir`, named by a hash of the Stan code, so an
#' unchanged model reuses its executable across sessions and compilation leaves
#' the budget after the first block. The runner sets that option; this function
#' fails loudly if it has not been set, because the cost of finding out late is
#' days.
#'
#' `cores = 1` because the runner puts one iteration on one worker: nesting
#' Stan's own parallelism inside that oversubscribes the machine.
#'
#' **Priors are fixed per cell and arm, not derived per realisation.** bayesnec
#' derives its default priors from the response vector and brms writes them into
#' the Stan source as literals, so every simulated dataset produced a textually
#' different program and recompiled: 5,622 programs for 406 units, 40 MB and
#' most of the runtime each. Measured directly -- refitting a second realisation
#' with default priors compiled two new programs, and refitting it with the
#' first realisation's priors compiled none.
#'
#' The priors used are still bayesnec's own defaults; they are derived once from
#' a reference realisation of each cell and arm and then held fixed. Each arm
#' keeps its own prior, derived from its own prepared data, so the arm-to-arm
#' contrast the study measures is unaffected. What is removed is
#' iteration-to-iteration prior jitter, which is nuisance variation: a prior
#' that changes with every dataset is not really a prior. The predictor range is
#' identical across realisations within a cell and arm, so the hard parameter
#' bounds in the Stan code -- which would truncate a posterior if they were
#' wrong -- do not vary at all; only the response-derived scales do, by a few
#' per cent.
#' @param prior A named list of `brmsprior` objects, one per equation, built
#'   once per cell and arm by `analysis/build_priors.R` and held fixed across
#'   iterations. See the note below on why.
fit_arm <- function(dat, arm, seed = 1L, iter = 4000, warmup = 2000,
                    adapt_delta = 0.99, max_treedepth = 12,
                    disp = c("none", "loglinear"), prior = NULL) {
  disp <- match.arg(disp)
  if (is.null(getOption("cmdstanr_write_stan_file_dir"))) {
    stop("set options(cmdstanr_write_stan_file_dir = ...) before fitting; ",
         "without it every model recompiles per session")
  }
  prep <- prepare_arm(dat, arm)
  if (identical(disp, "loglinear")) {
    # disp("power") is refused for a response whose fitted mean crosses zero,
    # which is exactly this case, so "loglinear" is the only form available.
    prep$formula <- stats::update(prep$formula, . ~ . + disp("loglinear"))
  }
  if (!prep$record$estimable) {
    return(list(fit = NULL, record = prep$record))
  }
  fit <- try(
    bayesnec::bnec(prep$formula, data = prep$data, family = prep$family,
                   prior = prior,
                   seed = seed, iter = iter, warmup = warmup,
                   control = list(adapt_delta = adapt_delta,
                                  max_treedepth = max_treedepth),
                   # No open_progress here: it is an rstan argument and the
                   # cmdstanr backend rejects it outright.
                   backend = "cmdstanr", cores = 1, chains = 4,
                   silent = 2, refresh = 0),
    silent = TRUE
  )
  if (inherits(fit, "try-error")) {
    prep$record$estimable <- FALSE
    prep$record$note <- paste("bnec() failed:",
                              conditionMessage(attr(fit, "condition")))
    return(list(fit = NULL, record = prep$record))
  }
  list(fit = fit, record = prep$record)
}
