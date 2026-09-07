#!/bin/bash
set -euo pipefail

# Rootless launcher for the WRF/WPS Apptainer image.
#
# The container filesystem is read-only; all writable state (model output, run
# directories) must live on the bind-mounted host DATA_DIR, exposed as /data.
#
# Expected host layout under DATA_DIR (bound to /data):
#   $DATA_DIR/GEOG   -> WPS_GEOG static data   (from 04_download_wps_geog.sh)
#   $DATA_DIR/BC     -> boundary-condition GRIB files
#   $DATA_DIR/RUNS   -> run directories / output (writable)
#
# Usage:
#   SIF=clam-wrf.sif DATA_DIR=/data/clam ./docker/run_apptainer.sh <command...>
#
# Examples (single node):
#   ./docker/run_apptainer.sh bash
#   ./docker/run_apptainer.sh mpirun -np 16 real.exe
#   ./docker/run_apptainer.sh mpirun -np 32 wrf.exe
#
# The compiled binaries live at /opt/arw inside the image:
#   /opt/arw/WRF/main/{real.exe,wrf.exe}
#   /opt/arw/WPS/{geogrid.exe,ungrib.exe,metgrid.exe}
# and the runtime environment is /opt/arw/arw_intel_env.sh (sourced below).

SIF="${SIF:-clam-wrf.sif}"
DATA_DIR="${DATA_DIR:-$PWD/data}"

if [ "$#" -eq 0 ]; then
  set -- bash
fi

if [ ! -f "${SIF}" ]; then
  echo "ERROR: SIF image not found: ${SIF}" >&2
  echo "Build it first with: ./docker/build_sif.sh" >&2
  exit 1
fi

# --bind exposes the host data dir; add PATH so binaries are callable by name.
exec apptainer exec \
  --bind "${DATA_DIR}:/data" \
  "${SIF}" \
  bash -c 'source /opt/arw/arw_intel_env.sh
           export PATH="/opt/arw/WRF/main:/opt/arw/WPS:${PATH}"
           exec "$@"' bash "$@"

# -----------------------------------------------------------------------------
# Multi-node runs (EWC VMs or HPC) with the container-bundled Intel MPI + SSH.
#
# The same SIF must be present at the same path on every node, and passwordless
# SSH must work between nodes. Intel MPI's Hydra launcher spawns the remote
# process manager; wrap that spawn in `apptainer exec` so remote ranks run
# inside the container too:
#
#   cat > hosts <<EOF
#   192.168.2.156:16
#   192.168.2.134:16
#   EOF
#
#   export I_MPI_HYDRA_BOOTSTRAP=ssh
#   # Run the remote Hydra proxy inside the same container image:
#   export I_MPI_HYDRA_BOOTSTRAP_EXEC="apptainer"
#   export I_MPI_HYDRA_BOOTSTRAP_EXEC_EXTRA_ARGS="exec --bind ${DATA_DIR}:/data ${SIF}"
#
#   apptainer exec --bind "${DATA_DIR}:/data" "${SIF}" \
#     bash -c 'source /opt/arw/arw_intel_env.sh
#              cd /data/RUNS/<cycle>
#              mpirun -f hosts -np 32 /opt/arw/WRF/main/wrf.exe'
#
# On a Slurm HPC you can instead let the scheduler place ranks and launch one
# container per task:
#   srun --mpi=pmi2 apptainer exec --bind /data:/data clam-wrf.sif \
#     bash -c 'source /opt/arw/arw_intel_env.sh && exec /opt/arw/WRF/main/wrf.exe'
# (requires I_MPI_PMI_LIBRARY pointing at the host PMI library, bound into the
#  container). Prefer the SSH model above when no scheduler/PMI is available.
# -----------------------------------------------------------------------------
