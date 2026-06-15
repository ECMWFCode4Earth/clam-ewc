#!/bin/bash
set -eo pipefail

# ============================================================
# Intel oneAPI installation script for CLAM WRF/WPS template
#
# Default mode:
#   - If Intel oneAPI is already installed, do nothing.
#   - If a local offline installer is found, use it.
#   - If no local installer is found, download the default
#     Intel oneAPI Toolkit 2026.0.0 offline installer.
#
# Default root installation:
#   /opt/intel/oneapi
#
# Usage:
#   ./01_install_intel_oneapi.sh
#
# Optional:
#   ONEAPI_INSTALLER=/path/to/intel-oneapi-toolkit-2026.0.0.198_offline.sh ./01_install_intel_oneapi.sh
#   ONEAPI_USER_INSTALL=1 ./01_install_intel_oneapi.sh
# ============================================================

ONEAPI_DEFAULT_URL="${ONEAPI_DEFAULT_URL:-https://registrationcenter-download.intel.com/akdlm/IRC_NAS/71180075-e4e3-4c6f-bbbb-19017ed0cf7d/intel-oneapi-toolkit-2026.0.0.198_offline.sh}"
ONEAPI_INSTALLER="${ONEAPI_INSTALLER:-}"
ONEAPI_USER_INSTALL="${ONEAPI_USER_INSTALL:-0}"

echo "============================================================"
echo "Intel oneAPI installation"
echo "============================================================"

# ------------------------------------------------------------
# Check existing installation
# ------------------------------------------------------------

if [ -f /opt/intel/oneapi/setvars.sh ]; then
  echo "Intel oneAPI already found:"
  echo "  /opt/intel/oneapi/setvars.sh"
  exit 0
fi

if [ -f "${HOME}/intel/oneapi/setvars.sh" ]; then
  echo "Intel oneAPI already found:"
  echo "  ${HOME}/intel/oneapi/setvars.sh"
  exit 0
fi

# ------------------------------------------------------------
# Find or download installer
# ------------------------------------------------------------

if [ -n "${ONEAPI_INSTALLER}" ]; then
  if [ ! -f "${ONEAPI_INSTALLER}" ]; then
    echo "ERROR: ONEAPI_INSTALLER was set, but file was not found:"
    echo "  ${ONEAPI_INSTALLER}"
    exit 1
  fi
else
  # Try to find a local installer in the current directory.
  LOCAL_INSTALLER="$(ls -1 ./intel-oneapi-toolkit-*_offline.sh 2>/dev/null | head -1 || true)"

  if [ -n "${LOCAL_INSTALLER}" ]; then
    ONEAPI_INSTALLER="${LOCAL_INSTALLER}"
  else
    ONEAPI_INSTALLER="./intel-oneapi-toolkit-2026.0.0.198_offline.sh"

    echo "No local Intel oneAPI offline installer found."
    echo "Downloading:"
    echo "  ${ONEAPI_DEFAULT_URL}"

    wget -O "${ONEAPI_INSTALLER}.tmp" "${ONEAPI_DEFAULT_URL}"
    mv "${ONEAPI_INSTALLER}.tmp" "${ONEAPI_INSTALLER}"
  fi
fi

chmod +x "${ONEAPI_INSTALLER}"

echo "Using installer:"
echo "  ${ONEAPI_INSTALLER}"

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------

if [ "${ONEAPI_USER_INSTALL}" = "1" ]; then
  echo "Running user installation."
  sh "${ONEAPI_INSTALLER}" -a --silent --eula accept
else
  echo "Running root/system installation."
  sudo sh "${ONEAPI_INSTALLER}" -a --silent --eula accept
fi

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

if [ -f /opt/intel/oneapi/setvars.sh ]; then
  ONEAPI_SETVARS="/opt/intel/oneapi/setvars.sh"
elif [ -f "${HOME}/intel/oneapi/setvars.sh" ]; then
  ONEAPI_SETVARS="${HOME}/intel/oneapi/setvars.sh"
else
  echo "ERROR: Intel oneAPI installation finished, but setvars.sh was not found."
  exit 1
fi

echo "Intel oneAPI setvars.sh found:"
echo "  ${ONEAPI_SETVARS}"

set +u
source "${ONEAPI_SETVARS}" --force
set -u

echo
echo "Checking Intel compilers:"
for cmd in icx icpx ifx mpiicx mpiicpx mpiifx; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} not found after loading oneAPI environment."
    exit 1
  fi
  echo "  ${cmd} -> $(command -v "${cmd}")"
done

echo
icx --version | head -1
ifx --version | head -1

echo
echo "Intel oneAPI installed and verified successfully."
