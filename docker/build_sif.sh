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

IMAGE="${IMAGE:-clam-wrf:latest}"
SIF="${SIF:-clam-wrf.sif}"

# Repository root (directory containing build_scripts/ and docker/).
CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Building Docker image ${IMAGE}"
docker build -t "${IMAGE}" -f "${CONTEXT_DIR}/docker/Dockerfile" "${CONTEXT_DIR}"

echo "==> Converting ${IMAGE} to ${SIF}"
# Pull straight from the local Docker daemon; no registry required.
apptainer build "${SIF}" "docker-daemon://${IMAGE}"

echo "==> Done: ${SIF}"
