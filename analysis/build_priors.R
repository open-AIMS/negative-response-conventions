## Build one fixed prior per cell and arm, from a reference realisation.
##
##   Rscript analysis/build_priors.R [workers]
##
## Run once, before the study. Every subsequent fit is handed the prior for its
## cell and arm, so the Stan program is identical across iterations and compiles
## once instead of once per fit. Measured before this existed: 5,622 Stan
## programs for 406 units, 16 GB, and most of the per-unit runtime.
##
## The reference realisation is iteration 0, which the study itself never uses,
## so no iteration in the analysis is privileged over the others.
##
## This also warms the compile cache: after it finishes, every Stan program the
## study needs already exists, which is what lets a large SLURM array start
## without hundreds of tasks racing to compile the same files.

ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) stop("run from the compendium root")
.libPaths(c(file.path(ROOT, "lib"), .libPaths()))
suppressMessages({ library(bayesnec); library(parallel) })
if (utils::packageVersion("bayesnec") < "2.1.3.33") {
  stop("bayesnec ", utils::packageVersion("bayesnec"), "; need >= 2.1.3.33")
}
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

CACHE <- Sys.getenv("NRC_STAN_CACHE", file.path(path.expand("~"), ".cache", "nrc-stan"))
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
options(cmdstanr_write_stan_file_dir = CACHE)
cat("stan cache:", CACHE, "\n")

workers <- as.integer(commandArgs(trailingOnly = TRUE)[1] %||% 14L)
dir.create(file.path(ROOT, "priors"), showWarnings = FALSE)

cl_tab <- cells()
todo <- expand.grid(row = seq_len(nrow(cl_tab)), arm = arm_names(),
                    stringsAsFactors = FALSE)
todo$cell <- cl_tab$cell[todo$row]
todo$path <- file.path(ROOT, "priors", sprintf("%s__%s.rds", todo$cell, todo$arm))
todo <- todo[!file.exists(todo$path), ]
cat(nrow(todo), "of", nrow(cl_tab) * length(arm_names()), "priors to build\n")
if (!nrow(todo)) quit(save = "no")

t0 <- Sys.time()
invisible(mclapply(seq_len(nrow(todo)), mc.cores = workers, mc.preschedule = FALSE,
  function(k) {
    u <- todo[k, ]
    dat <- cell_dataset(cl_tab[u$row, ], 0L)      # reference realisation
    res <- try(fit_arm(dat, u$arm, seed = 1L, disp = cl_tab$disp[u$row]),
               silent = TRUE)
    if (inherits(res, "try-error") || is.null(res$fit)) {
      cat("FAILED", u$cell, u$arm, "\n"); return(NULL)
    }
    pr <- try(bayesnec::get_priors(res$fit), silent = TRUE)
    if (inherits(pr, "try-error")) { cat("NO PRIOR", u$cell, u$arm, "\n"); return(NULL) }
    saveRDS(pr, u$path)
    cat("built", u$cell, u$arm, "|", length(pr), "equations\n")
    NULL
  }))
cat(sprintf("done in %.1f h; %d priors on disk; %d stan programs cached\n",
            as.numeric(difftime(Sys.time(), t0, units = "hours")),
            length(list.files(file.path(ROOT, "priors"), "\\.rds$")),
            length(list.files(CACHE, "\\.stan$"))))
