#!/bin/bash
set -euo pipefail

# =============================================================================
# Install Apptainer on Rocky Linux 9 or Ubuntu 24.04 (rootless-capable).
#
# Apptainer runs containers rootless via unprivileged user namespaces; the
# distro package is all that is required. This script picks the right method
# per distro and falls back to the official GitHub release packages.
#
# Usage:
#   ./container/install_apptainer.sh
#
# Optional:
#   APPTAINER_VERSION=1.3.6 ./container/install_apptainer.sh   # force GitHub package
# =============================================================================

APPTAINER_VERSION="${APPTAINER_VERSION:-}"
GH_BASE="https://github.com/apptainer/apptainer/releases/download"

# Run a command as root, using sudo only when not already root.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "ERROR: need root privileges and sudo is not available." >&2
    exit 1
  fi
}

if [ ! -r /etc/os-release ]; then
  echo "ERROR: /etc/os-release not found; unsupported system." >&2
  exit 1
fi
. /etc/os-release

arch="$(uname -m)"
if [ "${arch}" != "x86_64" ]; then
  echo "ERROR: only x86_64 is supported by this script (found ${arch})." >&2
  exit 1
fi

install_from_github_deb() {
  local ver="$1" tmp
  tmp="$(mktemp -d)"
  echo "==> Installing Apptainer ${ver} from GitHub (.deb)"
  curl -fL -o "${tmp}/apptainer.deb" \
    "${GH_BASE}/v${ver}/apptainer_${ver}_amd64.deb"
  as_root apt-get update
  as_root apt-get install -y "${tmp}/apptainer.deb"
  rm -rf "${tmp}"
}

install_from_github_rpm() {
  local ver="$1" tmp
  tmp="$(mktemp -d)"
  echo "==> Installing Apptainer ${ver} from GitHub (.rpm)"
  curl -fL -o "${tmp}/apptainer.rpm" \
    "${GH_BASE}/v${ver}/apptainer-${ver}-1.x86_64.rpm"
  as_root dnf install -y "${tmp}/apptainer.rpm"
  rm -rf "${tmp}"
}

case "${ID}:${VERSION_ID%%.*}" in
  ubuntu:24)
    echo "==> Detected Ubuntu ${VERSION_ID}"
    if [ -n "${APPTAINER_VERSION}" ]; then
      as_root apt-get update
      as_root apt-get install -y curl ca-certificates
      install_from_github_deb "${APPTAINER_VERSION}"
    else
      # Official Apptainer PPA.
      as_root apt-get update
      as_root apt-get install -y software-properties-common
      as_root add-apt-repository -y ppa:apptainer/ppa
      as_root apt-get update
      as_root apt-get install -y apptainer
    fi
    ;;

  rocky:9|rhel:9|almalinux:9|centos:9)
    echo "==> Detected ${PRETTY_NAME}"
    if [ -n "${APPTAINER_VERSION}" ]; then
      as_root dnf install -y curl ca-certificates
      install_from_github_rpm "${APPTAINER_VERSION}"
    else
      # Apptainer ships in EPEL for EL9.
      as_root dnf install -y epel-release
      as_root dnf install -y apptainer
    fi
    ;;

  *)
    echo "ERROR: unsupported distro '${ID} ${VERSION_ID}'." >&2
    echo "This script supports Ubuntu 24.04 and Rocky/RHEL/Alma/CentOS 9." >&2
    exit 1
    ;;
esac

# Warn if unprivileged user namespaces (needed for rootless) look disabled.
if [ -r /proc/sys/kernel/unprivileged_userns_clone ] && \
   [ "$(cat /proc/sys/kernel/unprivileged_userns_clone)" != "1" ]; then
  echo "WARNING: kernel.unprivileged_userns_clone is disabled; rootless"
  echo "         Apptainer may not work. Enable it with:"
  echo "         echo 'kernel.unprivileged_userns_clone=1' | sudo tee /etc/sysctl.d/90-userns.conf && sudo sysctl --system"
fi
if [ -r /proc/sys/user/max_user_namespaces ] && \
   [ "$(cat /proc/sys/user/max_user_namespaces)" = "0" ]; then
  echo "WARNING: user.max_user_namespaces is 0; rootless Apptainer will fail."
  echo "         Raise it, e.g.: sudo sysctl -w user.max_user_namespaces=15000"
fi

echo
echo "==> Apptainer installed:"
apptainer --version
