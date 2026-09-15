## Build the transcribed blocks for example7's worked-example figure.
##
## Emits two CSV texts: the simulated dataset the six conventions were all
## fitted to, and each convention's model-averaged curve thinned to a grid the
## vignette can hold inline. The vignette cannot read the compendium, so every
## figure it draws is transcribed; this is what produces that text.

ROOT <- "/mnt/c/Rworking/negative-response-conventions"
setwd(ROOT)
suppressMessages(library(bayesnec))
for (f in list.files("R", "\\.R$", full.names = TRUE)) source(f)

CELL <- "p1"
ITER <- exemplar_iteration(CELL, "measured")
cl   <- cells()[cells()$cell == CELL, ]
dat  <- cell_dataset(cl, ITER)

cat("cell", CELL, "iteration", ITER, "rows", nrow(dat),
    "negatives", sum(dat$sgr < 0), "\n")

## The dataset, as simulated. Each panel then shows what its own convention did
## to these same rows, which is the point of the figure.
d <- data.frame(x = round(dat$x, 5), sgr = round(dat$sgr, 5))
writeLines(c("x,sgr", apply(d, 1, paste, collapse = ",")),
           "/tmp/claude-1000/-mnt-c-Rworking-bayesnec/2727a26c-31c1-4a88-b409-1cd00894beec/scratchpad/panel_data.csv")

## A common log-spaced grid, so the six curves are read at the same
## concentrations and the block stays small enough to transcribe.
xs <- sort(unique(dat$x[dat$x > 0]))
grid <- exp(seq(log(min(xs)), log(max(xs)), length.out = 40))

rows <- do.call(rbind, lapply(arm_names(), function(a) {
  fit <- readRDS(file.path("fits_example", sprintf("%s__%s.rds", CELL, a)))
  pv  <- fit$w_pred_vals$data
  ## The Beta arm is fitted on (0, 1] after flooring, so its predictions are on
  ## that scale and must be multiplied back by the same factor the arm divided
  ## by before they can share an axis with the others. ppc_scale() is the one
  ## definition of that factor; the Gamma arm floors but does not scale.
  k <- ppc_scale(dat, a)
  data.frame(
    arm = a,
    x   = round(grid, 5),
    y   = round(approx(pv$x, pv$Estimate, grid)$y * k, 5),
    lo  = round(approx(pv$x, pv$Q2.5,     grid)$y * k, 5),
    hi  = round(approx(pv$x, pv$Q97.5,    grid)$y * k, 5))
}))
writeLines(c("arm,x,y,lo,hi", apply(rows, 1, paste, collapse = ",")),
           "/tmp/claude-1000/-mnt-c-Rworking-bayesnec/2727a26c-31c1-4a88-b409-1cd00894beec/scratchpad/panel_curves.csv")
cat("curve rows:", nrow(rows), "\n")
cat("scale factors:", paste(sprintf("%s=%.4f", arm_names(),
    sapply(arm_names(), function(a) ppc_scale(dat, a))), collapse = "  "), "\n")
