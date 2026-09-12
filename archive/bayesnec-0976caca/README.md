# Results from bayesnec 0976caca

The 100-iteration run reported here was produced against `bayesnec` at commit
`0976caca`, before the prior and initialisation work of September 2026 landed on
`dev`. It is kept because the vignette and the report quoted it, and a figure
that was published should remain checkable.

It is not comparable with the current run and must not be pooled with it. Three
changes between that commit and the one `hpc/bayesnec.lock` now names alter
every fit:

- **#304** rebuilt the `nec` and `ec50` priors on the log of the predictor. On
  the reference cell the `nec` prior went from `gamma(5, 2.666)` to
  `lognormal(0.615, 1.175)`. The consequence for this study is direct: the true
  ErC50 sat above the 99th percentile of its own prior under the old
  construction and sits at the 80th to 95th under the new one, which is the
  limitation the vignette recorded as the first thing to check if the default
  prior changed.
- **#307** and **#315** redefined the regularizing set. The study uses the
  default `uninformative` set, so this changes nothing here directly, and is
  named because it is part of the same release.
- **#312** rewrote the initial-value search to accept chains individually and to
  band the curve on level means, which changes the starting values of every fit
  in the study.

`report.html` is the rendered report as it stood against that commit, kept for
the same reason as the tables.

The per-unit `.rds` files are gone. They were moved aside on the cluster rather
than deleted, into a `superseded-<timestamp>/` directory, and then removed on
2026-09-12 by an `rsync --delete-excluded` in `hpc/deploy.sh` — which deletes
the paths named as exclusions rather than protecting them. The tables above are
therefore the record of that run, and the figures the vignette and the report
quoted from it remain checkable against them; the individual fits behind those
figures do not survive. `hpc/deploy.sh` now uses `--delete`, which leaves an
excluded path alone.
