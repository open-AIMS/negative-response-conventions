## Run one block of iterations across every cell and arm.
##
##   Rscript analysis/run_block.R <block> [workers] [iter_per_block]
##
## Blocks are balanced by design: block 1 runs iterations 1-50 in EVERY cell,
## block 2 runs 51-100, and so on. That is what makes an early collation
## meaningful -- after one block every cell has the same number of iterations,
## rather than two cells being finished and five not started. See
## REDESIGN-claude.md section 6.
##
## Resumable by existence check: a result file that already exists is skipped,
## so a crashed block is restarted with the same command and costs only the
## fits that had not finished.

## Run from the repository root.
ROOT <- getwd()
if (!dir.exists(file.path(ROOT, "R"))) {
  stop("run this from the compendium root: R/ not found in ", ROOT)
}

## .libPaths BEFORE library(). Loading bayesnec first takes whatever is in the
## user library -- 2.1.3.7 on this machine, which is the pre-#206 behaviour this
## study exists to measure past. The run would have completed and reported the
## old candidate set without any error. The assertion below is the backstop:
## a study measuring the wrong version is worse than one that refuses to start.
.libPaths(c(file.path(ROOT, "lib"), .libPaths()))
suppressMessages({
  library(bayesnec)
  library(parallel)
})
BAYESNEC_MIN <- "2.1.3.33"
if (utils::packageVersion("bayesnec") < BAYESNEC_MIN) {
  stop("bayesnec ", utils::packageVersion("bayesnec"), " loaded from ",
       dirname(find.package("bayesnec")), "; this study needs >= ", BAYESNEC_MIN)
}
for (f in list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)) source(f)

args <- commandArgs(trailingOnly = TRUE)
block <- as.integer(args[1] %||% 1L)
workers <- as.integer(args[2] %||% 20L)
per_block <- as.integer(args[3] %||% 50L)
## Optional fourth argument: a comma-separated list of cells, so the dispersion
## cells can be deferred. They answer question 6, which is the least central of
## the six, and holding them back takes a block from about 29 hours to 23.
only <- if (length(args) >= 4L) strsplit(args[4], ",")[[1]] else NULL

## cmdstanr rebuilds a model in a temporary directory unless told otherwise, so
## every fit would recompile. Point it at a cache that persists across blocks.
CACHE <- Sys.getenv("NRC_STAN_CACHE", file.path(path.expand("~"), ".cache", "nrc-stan"))
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
options(cmdstanr_write_stan_file_dir = CACHE)

iters <- seq((block - 1L) * per_block + 1L, block * per_block)
cl_tab <- cells()
if (!is.null(only)) {
  missing <- setdiff(only, cl_tab$cell)
  if (length(missing)) stop("no such cell: ", paste(missing, collapse = ", "))
  cl_tab <- cl_tab[cl_tab$cell %in% only, , drop = FALSE]
}

## Iteration-major, not cell-major. mclapply dispatches the queue in order, so
## ordering it by cell finishes one cell before starting the next: after 14
## hours the first attempt had p1 complete, p2 a third done and five cells
## empty. The block structure only delivers balance when a block finishes, and
## a block takes about three days at the measured rate of 42 worker-minutes per
## unit. Ordering by iteration first means every cell advances together, so the
## run can be stopped at any point and still give the same number of iterations
## in every cell.
queue <- do.call(rbind, lapply(iters, function(it) {
  do.call(rbind, lapply(seq_len(nrow(cl_tab)), function(i) {
    data.frame(row = i, cell = cl_tab$cell[i], arm = arm_names(),
               iteration = it, stringsAsFactors = FALSE)
  }))
}))
queue$path <- file.path(ROOT, "results", queue$cell, queue$arm,
                        sprintf("iter_%04d.rds", queue$iteration))
todo <- queue[!file.exists(queue$path), ]

cat(sprintf("block %d | %d cells x %d arms x %d iterations = %d units, %d to do\n",
            block, nrow(cl_tab), length(arm_names()), length(iters),
            nrow(queue), nrow(todo)))
if (!nrow(todo)) { cat("nothing to do\n"); quit(save = "no") }

invisible(lapply(unique(dirname(todo$path)), dir.create,
                 recursive = TRUE, showWarnings = FALSE))

t0 <- Sys.time()
res <- mclapply(seq_len(nrow(todo)), mc.cores = workers, mc.preschedule = FALSE,
  function(k) {
    u <- todo[k, ]
    out <- try(run_one(cl_tab[u$row, ], u$iteration, u$arm), silent = TRUE)
    if (inherits(out, "try-error")) {
      out <- list(cell = u$cell, iteration = u$iteration, arm = u$arm,
                  record = list(arm = u$arm, estimable = FALSE,
                                note = conditionMessage(attr(out, "condition"))),
                  estimates = NULL, weights = NULL)
    }
    saveRDS(out, u$path)
    NULL
  })

failed <- sum(vapply(res, inherits, logical(1), "try-error"))
cat(sprintf("block %d finished in %.1f h; %d worker errors\n", block,
            as.numeric(difftime(Sys.time(), t0, units = "hours")), failed))
