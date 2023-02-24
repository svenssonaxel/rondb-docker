# Environments for Machine Sizes

These environments represent all variables that are used when applying the flag `--size` in the [run.sh](/run.sh) script.

## Docker Section

- See Docker docs for info on resources
- Make sure the aggregate amount of memory **reservations** is
  allowed in the Docker settings! Otherwise the ndbds are likely to be
  killed by OOM (commonly disguised by signal 9)
- To check whether they are being used use `docker stats` on a running cluster
- "M" stands for MBytes
