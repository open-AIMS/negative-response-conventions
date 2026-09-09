## Build one fixed prior per cell and arm, from a reference realisation.
##
##   Rscript analysis/build_priors.R
##
## Run once, before the study, and commit the result: priors/ is tracked, so the
## exact priors every fit used are part of the record rather than something
## regenerated and hoped to match.
##
## No model is fitted here. bayesnec's default priors are a deterministic
## function of the model, family, predictor and response, and `get_priors()` has
## a method for a formula, so they can be computed directly. Verified against
## the fitting route: for nec4param and nec3param on the reference dataset the
## two agree exactly on prior, nlpar and both bounds.
##
## Why fix them at all. bayesnec derives priors from the response and brms
## writes them into the Stan source as literals, so every realisation produced a
## textually different program and recompiled -- 5,622 programs for 406 units,
## 16 GB, and most of the runtime. Holding the prior fixed within a cell and arm
## makes the program identical across iterations, so it compiles once.
##
## The reference is iteration 0, which the study never analyses, so no analysed
## realisation is privileged.

ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) stop("run from the compendium root")
.libPaths(c(file.path(ROOT, "lib"), .libPaths()))
suppressMessages(library(bayesnec))
if (utils::packageVersion("bayesnec") < "2.1.3.33") {
  stop("bayesnec ", utils::packageVersion("bayesnec"), "; need >= 2.1.3.33")
}
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

dir.create(file.path(ROOT, "priors"), showWarnings = FALSE)
cl_tab <- cells()
n <- 0L
for (i in seq_len(nrow(cl_tab))) {
  for (a in arm_names()) {
    p <- prepare_arm(cell_dataset(cl_tab[i, ], 0L), a)
    pr <- get_priors(bnf(p$formula), data = p$data, family = p$family)
    saveRDS(pr, file.path(ROOT, "priors",
                          sprintf("%s__%s.rds", cl_tab$cell[i], a)))
    cat(sprintf("%-8s %-9s %2d equations\n", cl_tab$cell[i], a, length(pr)))
    n <- n + 1L
  }
}
cat("\n", n, "priors written to priors/\n")
