## The four marine microalgal growth tests, analysed by the same six conventions
## as the simulation.
##
## These were computed when the vignette was built until the arms became
## model-averaged over the declining set: 24 model-averaged fits over 13 to 14
## equations each is a fifteen-hour precompile, which is not something to run on
## a workstation every time a sentence changes. They are run here instead, on
## the same machinery and against the same pinned bayesnec as the simulation,
## and the vignette transcribes the result. See hpc/README.md.
##
## What is lost by that move is stated rather than hidden: the case studies no
## longer track whatever version of bayesnec they ship beside. They report the
## commit in hpc/bayesnec.lock, exactly as the simulation does.

#' The four case-study datasets, prepared to the shape the arms expect
#'
#' Each row gets `x` (the tested concentration), `sgr` (the growth rate the
#' retaining conventions use), `below_limit` and `cens_bound`. Where the source
#' substituted a zero for a count below the limit of 10 cells per mL, `sgr` is
#' the growth rate that limit implies against the recorded starting density --
#' itself a substitution, which is why no convention is a true analysis of the
#' measurements on those two datasets.
case_datasets <- function() {
  if (!requireNamespace("bayesnec", quietly = TRUE)) stop("bayesnec is required")
  alga <- get("alga", envir = asNamespace("bayesnec"))
  alga$dataset <- factor(
    paste0(as.character(alga$species), ifelse(alga$contaminant == "B", "2", "")),
    levels = c("c_proliferum", "c_proliferum2", "r_salina", "r_salina2"))
  alga$below_limit <- alga$sgr_source == "substituted"
  # The growth rate implied by the counting limit of 10 cells per mL against the
  # starting density recorded for that test. Negative, and the tightest bound
  # the test supports for a row whose population fell below the limit.
  limit_rate <- (log(10) - log(alga$density_initial)) / alga$days
  alga$x <- alga$dose
  # What the retaining conventions analyse. A below-limit row has no measured
  # value, so every convention must substitute something and the limit rate is
  # what the retaining ones use -- itself a substitution, which is why no
  # convention is a true analysis of the measurements on the two Rhodomonas
  # tests.
  alga$sgr <- ifelse(alga$below_limit, limit_rate, alga$sgr)
  # The bound to censor at, which is not the same quantity. For a value that was
  # measured and came out negative it is zero: withdrawing the magnitude is the
  # convention under test. For a below-limit row it is the counting limit, which
  # is a stronger statement than "below zero" and is what the test does
  # establish. Getting this wrong censors nothing at all on a dataset with no
  # below-limit rows, because no measured value falls below the limit rate.
  alga$cens_bound <- ifelse(alga$below_limit, limit_rate, 0)
  split(alga, alga$dataset)
}

#' One line per dataset, for the report and for the vignette's table
case_summary <- function(dsets = case_datasets()) {
  do.call(rbind, lapply(names(dsets), function(nm) {
    d <- dsets[[nm]]
    data.frame(dataset = nm,
               species = as.character(d$species[1]),
               days = d$days[1],
               n = nrow(d),
               n_conc = length(unique(d$x)),
               control_rate = mean(d$sgr[d$x == 0]),
               below_limit = sum(d$below_limit),
               n_negative = sum(d$sgr < 0),
               prop_at_or_below_zero = mean(d$sgr <= 0),
               stringsAsFactors = FALSE)
  }))
}

#' The queue of case-study units, in a fixed order so an index means one thing
case_queue <- function() {
  dsets <- names(case_datasets())
  do.call(rbind, lapply(dsets, function(ds) {
    data.frame(dataset = ds, arm = arm_names(), stringsAsFactors = FALSE)
  }))
}

#' Everything one (dataset, arm) case unit contributes
#'
#' The same three estimates as the simulation, the model weights, and the
#' per-equation diagnostics with the weight each equation holds beside them --
#' which is the only way to read them, because an equation whose shape suits the
#' data badly fails the diagnostics whatever the data are doing and is given
#' almost no weight for the same reason.
run_case <- function(dataset, arm) {
  dsets <- case_datasets()
  if (!dataset %in% names(dsets)) stop("unknown dataset ", dataset)
  dat <- dsets[[dataset]]
  # No fixed prior here, unlike the simulation. Fixing one buys nothing: each
  # dataset and arm is fitted once, so there is no repetition for an identical
  # Stan program to save, and letting bnec() derive its own defaults from the
  # prepared data is the practice the case studies exist to show.
  res <- fit_arm(dat, arm, seed = 333L, prior = NULL)
  out <- list(dataset = dataset, arm = arm, record = res$record,
              estimates = NULL, weights = NULL, diagnostics = NULL,
              n_rows = nrow(dat), n_negative = sum(dat$sgr < 0),
              x_range = range(dat$x[dat$x > 0]))
  if (is.null(res$fit)) return(out)
  out$estimates <- arm_estimates(res$fit)
  out$weights <- try(arm_weights(res$fit), silent = TRUE)
  if (inherits(out$weights, "try-error")) out$weights <- NULL
  out$diagnostics <- try(arm_diagnostics(res$fit), silent = TRUE)
  if (inherits(out$diagnostics, "try-error")) out$diagnostics <- NULL
  out
}
