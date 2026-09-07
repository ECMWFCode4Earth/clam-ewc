#!/bin/bash
set -euo pipefail

# Build the multi-stage Docker image and convert it to an Apptainer SIF.
#
# Requires Docker (or a compatible daemon) and Apptainer on the build host.
# The SIF is portable and runs rootless on the EWC VMs and on HPC.
#
# Usage:
#   ./docker/build_sif.sh
#
# Overridable:
#   IMAGE=clam-wrf:latest  SIF=clam-wrf.sif  ./docker/build_sif.sh
#   SANDBOX=1  SBX=clam-sbx  ./docker/build_sif.sh   # also emit a sandbox dir
#     (use a sandbox on hosts where the SIF/FUSE mount fails, e.g. broken
#      fuse-overlayfs: the sandbox runs from a plain directory, no squashfuse)

IMAGE="${IMAGE:-clam-wrf:latest}"
SIF="${SIF:-clam-wrf.sif}"
SBX="${SBX:-clam-sbx}"

# Repository root (directory containing build_scripts/ and docker/).
CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Building Docker image ${IMAGE}"
docker build -t "${IMAGE}" -f "${CONTEXT_DIR}/docker/Dockerfile" "${CONTEXT_DIR}"

echo "==> Converting ${IMAGE} to ${SIF}"
# Pull straight from the local Docker daemon; no registry required.
apptainer build "${SIF}" "docker-daemon://${IMAGE}"

# Optional plain-directory sandbox for hosts where the SIF cannot be FUSE-mounted.
if [ "${SANDBOX:-0}" = "1" ]; then
  echo "==> Building sandbox ${SBX} from ${SIF}"
  rm -rf "${SBX}"
  apptainer build --sandbox "${SBX}" "${SIF}"
  echo "    run it with: IMG=${SBX} ./docker/run_apptainer.sh"
fi

echo "==> Done: ${SIF}"
