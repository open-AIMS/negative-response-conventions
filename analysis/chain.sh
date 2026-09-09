#!/bin/bash
# Blocks of 20 iterations, with a collation after each, so there is a balanced
# result to draft against roughly a day in rather than three days in.
# run_block.R skips units whose result file exists, so a re-run is free and an
# interrupted block resumes where it stopped.
cd /mnt/c/Rworking/negative-response-conventions
export NOT_CRAN=true
for b in 1 2 3 4 5; do
  echo "=== block $b (iterations $(( (b-1)*20+1 ))-$(( b*20 ))) starting $(date -Is) ===" >> chain.log
  Rscript analysis/run_block.R "$b" 20 20 >> chain.log 2>&1
  Rscript analysis/collate.R "results/metrics_$(( b*20 ))iter.csv" >> chain.log 2>&1
  echo "=== block $b collated $(date -Is) ===" >> chain.log
done
echo "=== 100 iterations per cell complete $(date -Is) ===" >> chain.log
