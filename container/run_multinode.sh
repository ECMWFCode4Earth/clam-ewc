#!/bin/bash
set -euo pipefail

# =============================================================================
# Multi-node orchestrator for the WRF/WPS Apptainer container.
#
# Splits a run into two phases:
#   Phase 1 (single node, inside the container): prep + WPS + real.exe. Runs the
#            bundled main_wrf.sh with MULTINODE_HOST_WRF=1 so run_real.sh stops
#            right after real.exe (it does NOT launch wrf.exe in-container).
#   Phase 2 (multiple nodes): wrf.exe launched by the HOST mpirun, one
#            `apptainer exec ... wrf.exe` per rank, so the executable resolves
#            INSIDE the container on every node (see container/run_apptainer.sh
#            for why the launcher must run on the host, not in the container).
#
# This script runs ON THE HOST. It sources the host Intel oneAPI environment so
# the host `mpirun` (Hydra launcher) is on PATH; wrf.exe itself uses the
# container's ABI-compatible Intel MPI. The host Intel MPI MUST be the SAME
# release as the one baked into the image.
#
# Requirements on every node:
#   - Apptainer + the SAME SIF at the SAME path
#   - Intel oneAPI (at least Intel MPI) at the SAME path, same release as the image
#   - passwordless SSH between nodes
#   - DATA_DIR on a SHARED filesystem, same path everywhere (so the run dir with
#     namelist.input / wrfinput / wrfbdy is visible to all ranks)
#
# Env:
#   IMG / SIF     image to run: a SIF or a sandbox dir. Default: clam-wrf.sif
#   DATA_DIR      host dir with GEOG/ BC/ RUNS/, bound to /data. Default: $PWD/data
#   RUN_VARIANT   bundled run_scripts set: default | large | opendata. Default: default
#   RUN_SCRIPTS   optional host run_scripts dir to override the selected variant
#   HOSTS         REQUIRED for phase 2: comma-separated node list, e.g. vm01,vm03
#   PPN           ranks per node (phase 2). Default: 16
#   NP            total ranks (phase 2). Default: PPN * number_of_hosts
#   CYCLE         run-dir name under RUNS, e.g. 2018060100_europe. Default: the
#                 newest directory under DATA_DIR/RUNS after phase 1
#   ONEAPI_SETVARS host oneAPI setvars.sh to source for mpirun.
#                  Default: /opt/intel/oneapi/setvars.sh
#   RUN_DATE/CYC/FLENGTH/REAL_NP  optional, forwarded into phase 1 (honored by
#                  the opendata variant; the default/large variants hardcode dates)
#   SKIP_PHASE1   set to 1 to skip phase 1 (reuse an existing prepared run dir)
#
# Usage:
#   HOSTS=vm01,vm03 PPN=16 DATA_DIR=/data/clam IMG=/mnt/data1/clam-wrf.sif \
#     ./container/run_multinode.sh
#
#   RUN_VARIANT=opendata HOSTS=vm01,vm03 PPN=16 DATA_DIR=/data/clam \
#     IMG=/mnt/data1/clam-wrf.sif ./container/run_multinode.sh
# =============================================================================

IMG="${IMG:-${SIF:-clam-wrf.sif}}"
DATA_DIR="${DATA_DIR:-$PWD/data}"
RUN_VARIANT="${RUN_VARIANT:-default}"
RUN_SCRIPTS="${RUN_SCRIPTS:-}"
PPN="${PPN:-16}"
ONEAPI_SETVARS="${ONEAPI_SETVARS:-/opt/intel/oneapi/setvars.sh}"
SKIP_PHASE1="${SKIP_PHASE1:-0}"

if [ ! -e "${IMG}" ]; then
  echo "ERROR: image not found: ${IMG} (SIF file or sandbox directory)" >&2
  echo "Build a SIF with: ./container/build_sif.sh" >&2
  exit 1
fi

# Map RUN_VARIANT to the bundled run_scripts directory inside the image.
case "${RUN_VARIANT}" in
  default)  RS_DIR=/opt/arw/run_scripts ;;
  large)    RS_DIR=/opt/arw/run_scripts_large ;;
  opendata) RS_DIR=/opt/arw/run_scripts_opendata ;;
  *)
    echo "ERROR: invalid RUN_VARIANT='${RUN_VARIANT}' (use: default|large|opendata)" >&2
    exit 1
    ;;
esac

BINDS=(--bind "${DATA_DIR}:/data")
[ -n "${RUN_SCRIPTS}" ] && BINDS+=(--bind "${RUN_SCRIPTS}:${RS_DIR}")

# ---------------------------------------------------------------------------
# Phase 1: single node, inside the container -> prep + WPS + real.exe.
# MULTINODE_HOST_WRF=1 makes run_real.sh stop after real.exe.
# ---------------------------------------------------------------------------
if [ "${SKIP_PHASE1}" != "1" ]; then
  echo "==> Phase 1 (single node): WPS + real.exe in the container"

  EXEC_ENV=(--env MULTINODE_HOST_WRF=1)
  [ -n "${RUN_DATE:-}" ] && EXEC_ENV+=(--env "RUN_DATE=${RUN_DATE}")
  [ -n "${CYC:-}" ]      && EXEC_ENV+=(--env "CYC=${CYC}")
  [ -n "${FLENGTH:-}" ]  && EXEC_ENV+=(--env "FLENGTH=${FLENGTH}")
  [ -n "${REAL_NP:-}" ]  && EXEC_ENV+=(--env "REAL_NP=${REAL_NP}")

  apptainer exec \
    "${EXEC_ENV[@]}" \
    "${BINDS[@]}" \
    "${IMG}" \
    bash -c 'source /opt/arw/arw_intel_env.sh
             export PATH="/opt/arw/WRF/main:/opt/arw/WPS:${PATH}"
             cd "'"${RS_DIR}"'"
             exec bash main_wrf.sh'
else
  echo "==> Phase 1 skipped (SKIP_PHASE1=1)"
fi

# ---------------------------------------------------------------------------
# Resolve the run directory produced by phase 1 (container path /data/RUNS/...).
# ---------------------------------------------------------------------------
if [ -n "${CYCLE:-}" ]; then
  RUN_SUBDIR="${CYCLE}"
else
  newest="$(ls -1dt "${DATA_DIR}/RUNS"/*/ 2>/dev/null | head -1 || true)"
  if [ -z "${newest}" ]; then
    echo "ERROR: no run directory found under ${DATA_DIR}/RUNS. Set CYCLE=<name>." >&2
    exit 1
  fi
  RUN_SUBDIR="$(basename "${newest}")"
fi
echo "==> Run directory: ${DATA_DIR}/RUNS/${RUN_SUBDIR} (container: /data/RUNS/${RUN_SUBDIR})"

# ---------------------------------------------------------------------------
# Phase 2: multi-node wrf.exe via HOST mpirun + per-rank apptainer exec.
# ---------------------------------------------------------------------------
if [ -z "${HOSTS:-}" ]; then
  echo "ERROR: HOSTS is required for phase 2, e.g. HOSTS=vm01,vm03" >&2
  exit 1
fi

if [ -z "${NP:-}" ]; then
  nhosts="$(awk -F, '{print NF}' <<< "${HOSTS}")"
  NP=$(( nhosts * PPN ))
fi

# Source the host oneAPI env so `mpirun` (the host Hydra launcher) is on PATH.
if [ ! -r "${ONEAPI_SETVARS}" ]; then
  echo "ERROR: oneAPI setvars not found/readable: ${ONEAPI_SETVARS}" >&2
  echo "Install Intel oneAPI on the host or set ONEAPI_SETVARS=<path>/setvars.sh" >&2
  exit 1
fi
set +u
# shellcheck disable=SC1090
source "${ONEAPI_SETVARS}" --force >/dev/null
set -u
command -v mpirun >/dev/null || { echo "ERROR: mpirun not on PATH after sourcing ${ONEAPI_SETVARS}" >&2; exit 1; }

echo "==> Phase 2 (multi node): wrf.exe on HOSTS=${HOSTS} PPN=${PPN} NP=${NP}"
mpirun -hosts "${HOSTS}" -ppn "${PPN}" -np "${NP}" \
  apptainer exec --bind "${DATA_DIR}:/data" "${IMG}" \
    bash -c 'source /opt/arw/arw_intel_env.sh
             cd "/data/RUNS/'"${RUN_SUBDIR}"'"
             ulimit -s unlimited
             exec /opt/arw/WRF/main/wrf.exe'

echo "==> Done. Check /data/RUNS/${RUN_SUBDIR}/rsl.out.0000 for 'SUCCESS COMPLETE WRF'."
