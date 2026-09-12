## Fit and keep one exemplar, chosen by index.
##
##   Rscript analysis/run_exemplar.R <index>     # 1..66
##
## The study's own runners skip a unit whose result file exists, which is what
## makes a resubmitted array cheap and what stops them being used to add the
## saved fits after the fact. This fits the exemplars directly and skips on the
## FIT file rather than on the result file, so it can be run against a completed
## study without disturbing it.
##
## The fit is identical to the one the study recorded: the data are a
## deterministic function of cell and iteration, and the sampler seed is a
## deterministic function of iteration, so refitting reproduces it.

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

cl_tab <- cells()
sim <- do.call(rbind, lapply(seq_len(nrow(cl_tab)), function(i) {
  data.frame(kind = "sim", row = i, cell = cl_tab$cell[i], arm = arm_names(),
             stringsAsFactors = FALSE)
}))
sim$iteration <- mapply(exemplar_iteration, sim$cell, sim$arm)
cas <- case_queue()
cas <- data.frame(kind = "case", row = NA_integer_, cell = cas$dataset,
                  arm = cas$arm, iteration = NA_integer_, stringsAsFactors = FALSE)
queue <- rbind(sim, cas)

idx <- as.integer(commandArgs(trailingOnly = TRUE)[1])
if (is.na(idx) || idx < 1L || idx > nrow(queue)) {
  stop("index outside 1:", nrow(queue))
}
u <- queue[idx, ]
dir_out <- if (u$kind == "sim") "fits" else "fits_cases"
path <- file.path(ROOT, dir_out, sprintf("%s__%s.rds", u$cell, u$arm))
if (file.exists(path)) { cat("already have:", path, "\n"); quit(save = "no") }

t0 <- Sys.time()
if (u$kind == "sim") {
  invisible(run_one(cl_tab[u$row, ], u$iteration, u$arm, fit_path = path))
} else {
  invisible(run_case(u$cell, u$arm, fit_path = path))
}
cat(sprintf("exemplar %d  %s %s/%s%s  %.1f min\n", idx, u$kind, u$cell, u$arm,
            if (u$kind == "sim") paste0("/iter ", u$iteration) else "",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
