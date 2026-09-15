## Fit every convention to ONE simulated dataset, for the worked-example figure.
##
##   Rscript analysis/run_example_panel.R <index>     # 1..6
##
## The saved exemplars in fits/ are one per cell AND arm, and exemplar_iteration()
## draws a different realisation for each arm, so they cannot be put side by side:
## a difference between two of those panels is partly the convention and partly
## the realisation. This fits all six arms to the same dataset, which is what
## makes the panels attributable to the convention alone.
##
## The realisation is p1's `measured` exemplar, chosen by a seed fixed on the
## cell and arm names before any result was seen, rather than picked after
## looking at the fits.

ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) stop("run from the compendium root")
if (dir.exists(file.path(ROOT, "lib"))) {
  .libPaths(c(file.path(ROOT, "lib"), .libPaths()))
}
suppressMessages(library(bayesnec))
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

CACHE <- Sys.getenv("NRC_STAN_CACHE", file.path(path.expand("~"), ".cache", "nrc-stan"))
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
options(cmdstanr_write_stan_file_dir = CACHE)

CELL <- "p1"
ITER <- exemplar_iteration(CELL, "measured")

idx <- as.integer(commandArgs(trailingOnly = TRUE)[1])
arms <- arm_names()
if (is.na(idx) || idx < 1L || idx > length(arms)) stop("index outside 1:", length(arms))
arm <- arms[idx]

dir.create(file.path(ROOT, "fits_example"), showWarnings = FALSE)
path <- file.path(ROOT, "fits_example", sprintf("%s__%s.rds", CELL, arm))
if (file.exists(path)) { cat("already have:", path, "\n"); quit(save = "no") }

cl <- cells()[cells()$cell == CELL, ]
t0 <- Sys.time()
invisible(run_one(cl, ITER, arm, fit_path = path))
cat(sprintf("panel %s/%s iter %d  %.1f min\n", CELL, arm, ITER,
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
