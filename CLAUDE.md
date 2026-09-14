# Notes for Claude Code sessions in this repository

A research compendium (see `/mnt/c/Rworking/CLAUDE.md` section 2). Quarto for
reporting, `bayesnec` for the fits. No R CMD check, no GitHub Actions.

## Results that are kept but not reported

`results/metrics_disp.csv`, `results/diagnostics_disp.csv`, `priors_disp/` and
`archive/disp-probe/` are from a dispersion sweep that neither the report nor
the `example7` vignette cites. Five arms on the four precision cells, 100
realisations each, asking whether letting a family's dispersion vary along the
curve repairs the conventions that impose the zero boundary through the response
distribution. Code: `R/disp_arms.R`, `analysis/run_disp_sweep.R`.

It was left out because the outcome is mostly negative. A dispersion sub-model
does not correct the Gamma's variance structure; the Beta needs no correction
and both forms make it worse; and adding one to a Gaussian, whose variance model
is already correct, manufactures a gradient the data do not have. One result is
unexplained rather than negative: the Beta's ErC50 comes within two per cent at
every precision under `disp("loglinear")`, against -4.4% to -5.8% without it,
while that arm's variance model deteriorates. Not a variance effect, mechanism
unknown.

The five fits in `archive/disp-probe/` preceded that sweep and used `bnec()`'s
own default priors rather than the fixed ones, on one cell. They are not
comparable with the sweep and are kept only as the record of what prompted it.

Do not delete any of it, and do not cite it without raising the question first.

`results/ppc_spread.csv` is a different thing and **is** cited, in Section 5.3 of
the vignette. It measures whether a family reproduces the generated residual
spread; it does not attempt to correct one. Its code, `R/ppc.R` and
`analysis/run_ppc.R`, sits beside the dispersion work and the two are easily
confused.
