#!/bin/bash
set -euo pipefail

# Build the multi-stage Docker image and convert it to an Apptainer SIF.
#
# Requires Docker (or a compatible daemon) and Apptainer on the build host.
# The SIF is portable and runs rootless on the EWC VMs and on HPC.
#
# Usage:
#   ./container/build_sif.sh
#
# Overridable:
#   IMAGE=clam-wrf:latest  SIF=clam-wrf.sif  ./container/build_sif.sh
#   WRF_OPENDATA=1  ./container/build_sif.sh            # build the ECMWF open-data
#     WPS variant (patched ungrib); default 0 keeps the shipped ungrib
#   SANDBOX=1  SBX=clam-sbx  ./container/build_sif.sh   # also emit a sandbox dir
#     (use a sandbox on hosts where the SIF/FUSE mount fails, e.g. broken
#      fuse-overlayfs: the sandbox runs from a plain directory, no squashfuse)

IMAGE="${IMAGE:-clam-wrf:latest}"
SIF="${SIF:-clam-wrf.sif}"
SBX="${SBX:-clam-sbx}"
WRF_OPENDATA="${WRF_OPENDATA:-0}"

# Repository root (directory containing build_scripts/ and container/).
CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Building Docker image ${IMAGE} (WRF_OPENDATA=${WRF_OPENDATA})"
docker build \
  --build-arg WRF_OPENDATA="${WRF_OPENDATA}" \
  -t "${IMAGE}" -f "${CONTEXT_DIR}/container/Dockerfile" "${CONTEXT_DIR}"

echo "==> Converting ${IMAGE} to ${SIF}"
# Pull straight from the local Docker daemon; no registry required.
apptainer build "${SIF}" "docker-daemon://${IMAGE}"

# Optional plain-directory sandbox for hosts where the SIF cannot be FUSE-mounted.
if [ "${SANDBOX:-0}" = "1" ]; then
  echo "==> Building sandbox ${SBX} from ${SIF}"
  rm -rf "${SBX}"
  apptainer build --sandbox "${SBX}" "${SIF}"
  echo "    run it with: IMG=${SBX} ./container/run_apptainer.sh"
fi

echo "==> Done: ${SIF}"
