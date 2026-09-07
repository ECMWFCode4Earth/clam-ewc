#!/bin/bash
set -euo pipefail

# =============================================================================
# Install Docker Engine on Rocky Linux 9 or Ubuntu 24.04.
#
# Installs docker-ce + CLI + containerd + buildx/compose plugins from Docker's
# official repository, enables the service, and (optionally) adds the invoking
# user to the "docker" group so the daemon can be used without sudo.
#
# Usage:
#   ./docker/install_docker.sh
#
# Optional:
#   ADD_USER_TO_DOCKER_GROUP=0 ./docker/install_docker.sh   # skip group change
# =============================================================================

ADD_USER_TO_DOCKER_GROUP="${ADD_USER_TO_DOCKER_GROUP:-1}"

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

DOCKER_PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

case "${ID}:${VERSION_ID%%.*}" in
  ubuntu:24)
    echo "==> Detected Ubuntu ${VERSION_ID}"
    # Remove distro-shipped conflicting packages (ignore if absent).
    as_root apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true

    as_root apt-get update
    as_root apt-get install -y ca-certificates curl
    as_root install -m 0755 -d /etc/apt/keyrings
    as_root curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      -o /etc/apt/keyrings/docker.asc
    as_root chmod a+r /etc/apt/keyrings/docker.asc

    # shellcheck disable=SC1091
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      | as_root tee /etc/apt/sources.list.d/docker.list >/dev/null

    as_root apt-get update
    as_root apt-get install -y "${DOCKER_PKGS[@]}"
    ;;

  rocky:9|rhel:9|almalinux:9|centos:9)
    echo "==> Detected ${PRETTY_NAME}"
    as_root dnf remove -y docker docker-client docker-client-latest docker-common \
      docker-latest docker-latest-logrotate docker-logrotate docker-engine podman runc 2>/dev/null || true

    as_root dnf -y install dnf-plugins-core
    # The CentOS repo definition is the one Docker publishes for RHEL-family EL9.
    as_root dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    as_root dnf -y install "${DOCKER_PKGS[@]}"
    ;;

  *)
    echo "ERROR: unsupported distro '${ID} ${VERSION_ID}'." >&2
    echo "This script supports Ubuntu 24.04 and Rocky/RHEL/Alma/CentOS 9." >&2
    exit 1
    ;;
esac

echo "==> Enabling and starting the Docker service"
as_root systemctl enable --now docker

# Allow the invoking user to talk to the daemon without sudo.
if [ "${ADD_USER_TO_DOCKER_GROUP}" = "1" ] && [ "$(id -u)" -ne 0 ]; then
  target_user="${SUDO_USER:-$USER}"
  echo "==> Adding user '${target_user}' to the 'docker' group"
  as_root groupadd -f docker
  as_root usermod -aG docker "${target_user}"
  echo "    Log out and back in (or run 'newgrp docker') for this to take effect."
fi

echo
echo "==> Docker installed:"
as_root docker version --format '{{.Server.Version}}' 2>/dev/null || as_root docker --version
