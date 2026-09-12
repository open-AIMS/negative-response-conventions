## Run exactly one (dataset, arm) case-study unit, chosen by index.
##
##   Rscript analysis/run_case.R <index>
##
## Twenty-four units: four marine microalgal growth tests by six conventions.
## One SLURM array task is one unit on one dedicated core, the same arrangement
## the simulation uses and for the same reason.
##
## Idempotent by an existence check, so a resubmitted array only redoes what is
## missing.

ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) stop("run from the compendium root")
if (dir.exists(file.path(ROOT, "lib"))) {
  .libPaths(c(file.path(ROOT, "lib"), .libPaths()))
}
suppressMessages(library(bayesnec))
if (utils::packageVersion("bayesnec") < "2.1.3.33") {
  stop("bayesnec ", utils::packageVersion("bayesnec"), " from ",
       dirname(find.package("bayesnec")), "; this study needs >= 2.1.3.33")
}
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

CACHE <- Sys.getenv("NRC_STAN_CACHE", file.path(path.expand("~"), ".cache", "nrc-stan"))
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
options(cmdstanr_write_stan_file_dir = CACHE)

args <- commandArgs(trailingOnly = TRUE)
idx <- as.integer(args[1])
queue <- case_queue()
if (is.na(idx) || idx < 1L || idx > nrow(queue)) {
  stop("index ", args[1], " outside 1:", nrow(queue))
}
u <- queue[idx, ]
path <- file.path(ROOT, "results_cases", u$dataset,
                  sprintf("%s.rds", u$arm))
if (file.exists(path)) {
  cat("already done:", path, "\n"); quit(save = "no")
}
dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

t0 <- Sys.time()
out <- try(run_case(u$dataset, u$arm,
                    fit_path = file.path(ROOT, "fits_cases",
                                         sprintf("%s__%s.rds", u$dataset, u$arm))),
           silent = TRUE)
if (inherits(out, "try-error")) {
  out <- list(dataset = u$dataset, arm = u$arm,
              record = list(arm = u$arm, estimable = FALSE,
                            note = conditionMessage(attr(out, "condition"))),
              estimates = NULL, weights = NULL, diagnostics = NULL)
}
saveRDS(out, path)
cat(sprintf("case %d  %s/%s  %.1f min\n", idx, u$dataset, u$arm,
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
