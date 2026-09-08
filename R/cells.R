## The design cells.
##
## Seven, plus a dispersion factor on two of them. See REDESIGN-claude.md
## section 4 for which question each answers.
##
## `sigma_mode = "absolute"` throughout the precision axis, and the reason is
## recorded at length in R/simulate.R: under `sigma_mode = "cv"` the generating
## model is exactly equivariant in the growth rate, so every arm returns the
## same answer at every R and the axis measures nothing. Holding the control
## residual SD fixed in absolute terms is what lets R enter as signal-to-noise,
## which is what makes it a measurement-precision axis.

CV_REF <- 0.096   # control coefficient of variation at the reference cell
R_REF  <- 2.3     # control fold-change at the reference cell

## The residual scale is CONSTANT along the curve in every cell.
##
## The previous study generated it rising 8.09-fold from control to lower
## asymptote and called that figure "calibrated from the real data". Measured
## again on `alga`, within-dose SD against position on the curve, substituted
## rows excluded and groups of fewer than four dropped:
##
##   c_proliferum   14 groups  fitted ratio 14.14  slope p < 0.001
##   c_proliferum2  13 groups  fitted ratio  1.43  slope p = 0.36
##   r_salina       10 groups  fitted ratio  1.21  slope p = 0.52
##   r_salina2      12 groups  fitted ratio  1.51  slope p = 0.44
##
## One dataset of four has a gradient. 8.09 is not a fitted value at all: it is
## the largest single dose-group ratio on that one dataset, n = 5 against a
## control of n = 20, where the fitted value is 14.1. Before excluding
## substituted rows, r_salina appeared to show ratios of 24 and 21 -- those
## groups mix substituted zeros with measurements, so part of what was
## calibrated against was the convention under test.
##
## Generating every cell at 8.09 therefore asserted as universal something seen
## in one dataset, and made every arm misspecified in the same way, which is a
## confound shared by the whole comparison rather than a feature of it. Flat.

cells <- function() {
  base <- data.frame(
    cell        = c("p1", "p2", "p3", "p4", "d2", "d8", "ctl"),
    delta       = c(   4,    4,    4,    4,    2,    8,     4),
    top_factor  = c( 2.0,  2.0,  2.0,  2.0,  2.0,  2.0,   1.0),
    R           = c( 2.3,  3.3,   17,   73,  2.3,  2.3,   2.3),
    answers     = c("Q1,Q2", "Q2", "Q2", "Q1,Q2", "Q3", "Q3", "Q4"),
    stringsAsFactors = FALSE
  )
  # Homoscedastic generation, and bnec()'s default homoscedastic fit, so the
  # mean structure of every candidate is the only thing under test.
  base$sigma_ratio <- 1
  base$disp <- "none"
  out <- base
  out$sigma_0_abs <- sigma_0_at(CV_REF, R_ref = R_REF)
  # The control CV each cell actually realises, which is what the report plots
  # on the precision axis: sigma_0 is held fixed while top rises with R.
  out$cv_control <- out$sigma_0_abs / (log(out$R) / 7)
  out
}

#' The truth, design and true endpoints for one cell
cell_truth <- function(cl) {
  tr <- sim_truth(R = cl$R, delta = cl$delta)
  dz <- sim_design(tr, top_factor = cl$top_factor)
  mu <- nec4param_curve(dz$x, tr$top, tr$bot, tr$beta, tr$nec)
  list(
    truth = tr,
    design = dz,
    # Tolerance rather than `<= 0`: at top_factor = 1 the highest design point
    # sits on the crossing, so a strict test flips on floating point.
    prop_negative = mean(mu <= 1e-10),
    true_values = c(ErC10 = true_ecx(tr, 10),
                    ErC50 = true_ecx(tr, 50),
                    NSEC  = tr$nec)
  )
}

#' One simulated dataset for one cell and iteration
#'
#' The seed is a pure function of cell and iteration, so every arm within an
#' iteration sees the same dataset and all contrasts are paired, and so a lost
#' block regenerates identically.
cell_dataset <- function(cl, iteration) {
  ct <- cell_truth(cl)
  seed <- as.integer(1e6 + 1000 * match(cl$cell, cells()$cell) + iteration)
  simulate_dataset(ct$truth, ct$design,
                   sigma_ratio = cl$sigma_ratio,
                   sigma_mode = "absolute", sigma_0_abs = cl$sigma_0_abs,
                   seed = seed)
}
