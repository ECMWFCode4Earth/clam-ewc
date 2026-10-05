#!/bin/bash
set -euo pipefail

# Rootless launcher for the WRF/WPS container.
#
# The image bakes in the run_scripts and symlinks $ARW_ROOT/{GEOG,BC,RUNS} to
# the /data bind mount, so a SINGLE bind of DATA_DIR is all that is required.
#
# Expected host layout under DATA_DIR (bound to /data):
#   $DATA_DIR/GEOG   -> WPS_GEOG static data   (from 04_download_wps_geog.sh)
#   $DATA_DIR/BC     -> boundary-condition GRIB files (from download_bc.sh)
#   $DATA_DIR/RUNS   -> run directories / output (writable)
#
# Env:
#   IMG          image to run: a SIF (clam-wrf.sif) OR a sandbox directory.
#                Default: clam-wrf.sif  (use a sandbox where SIF/FUSE mount fails)
#   DATA_DIR     host dir with GEOG/ BC/ RUNS/ (bound to /data). Default: $PWD/data
#   RUN_SCRIPTS  optional host run_scripts dir to override the bundled copy
#                (handy for editing RUN_DATE/IPs without rebuilding)
#
# Usage:
#   IMG=clam-wrf.sif DATA_DIR=/data/clam ./docker/run_apptainer.sh            # full pipeline
#   ./docker/run_apptainer.sh bash                                            # interactive shell
#   ./docker/run_apptainer.sh mpirun -np 4 real.exe
#
# With no arguments it runs the full orchestrator (main_wrf.sh: WPS -> real -> wrf).

IMG="${IMG:-clam-wrf.sif}"
DATA_DIR="${DATA_DIR:-$PWD/data}"
RUN_SCRIPTS="${RUN_SCRIPTS:-}"

if [ ! -e "${IMG}" ]; then
  echo "ERROR: image not found: ${IMG} (SIF file or sandbox directory)" >&2
  echo "Build a SIF with: ./docker/build_sif.sh" >&2
  echo "or a sandbox with: apptainer build --sandbox clam-sbx clam-wrf.sif" >&2
  exit 1
fi

BINDS=(--bind "${DATA_DIR}:/data")
[ -n "${RUN_SCRIPTS}" ] && BINDS+=(--bind "${RUN_SCRIPTS}:/opt/arw/run_scripts")

# Default action: run the full pipeline from the bundled run_scripts.
if [ "$#" -eq 0 ]; then
  set -- bash -c 'cd /opt/arw/run_scripts && exec bash main_wrf.sh'
fi

# Source the runtime env and make the binaries callable by name, then run.
# No `exec` here so any post-run steps below still execute.
apptainer exec \
  "${BINDS[@]}" \
  "${IMG}" \
  bash -c 'source /opt/arw/arw_intel_env.sh
           export PATH="/opt/arw/WRF/main:/opt/arw/WPS:${PATH}"
           exec "$@"' bash "$@"
rc=$?

# Add any post-run steps here (they run after the container exits).

exit "$rc"

# -----------------------------------------------------------------------------
# Multi-node runs (EWC VMs or HPC).
#
# Run mpirun ON THE HOST and make each rank `apptainer exec ... wrf.exe`, so the
# executable resolves INSIDE the container on every node. Launching mpirun from
# inside the container instead makes the remote Hydra proxy run on the bare host,
# where /opt/arw/WRF/main/wrf.exe does not exist -> "execvp error on file
# wrf.exe (No such file or directory)".
#
# Requirements on every node:
#   - Intel MPI available on the host, SAME release as in the image (mpirun is
#     the host launcher; wrf.exe uses the container's ABI-compatible Intel MPI)
#   - apptainer + the SAME SIF at the SAME path
#   - passwordless SSH between nodes
#   - the run directory reachable on all nodes (shared FS, or DATA_DIR on a
#     shared mount) so namelist.input / wrfinput are visible everywhere
#
#   DATA_DIR=/data/clam
#   SIF=/mnt/data1/clam-wrf.sif
#   CYCLE=<cycle>
#
#   # -ppn = ranks per node; -np = total ranks
#   mpirun -hosts vm01,vm03 -ppn 16 -np 32 \
#     apptainer exec --bind "${DATA_DIR}:/data" "${SIF}" \
#       bash -c 'source /opt/arw/arw_intel_env.sh
#                cd /data/RUNS/'"${CYCLE}"'
#                exec /opt/arw/WRF/main/wrf.exe'
#
# On a Slurm HPC, let the scheduler place ranks and launch one container per task
# (requires I_MPI_PMI_LIBRARY pointing at the host PMI library, bound in):
#   srun --mpi=pmi2 apptainer exec --bind /data:/data clam-wrf.sif \
#     bash -c 'source /opt/arw/arw_intel_env.sh
#              cd /data/RUNS/<cycle>
#              exec /opt/arw/WRF/main/wrf.exe'
# -----------------------------------------------------------------------------
