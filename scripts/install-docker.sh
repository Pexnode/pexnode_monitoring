#!/bin/bash
# Install Docker on host (called by enroll-host.sh)

set -Eeuo pipefail

echo "[docker] Ensuring Docker is installed..."

if command -v docker >/dev/null 2>&1; then
  echo "[docker] Docker already installed"
else
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS="$ID"
  else
    echo "[docker] Cannot detect OS (missing /etc/os-release)"
    exit 1
  fi

  case "$OS" in
    ubuntu|debian)
      apt-get update -qq
      apt-get install -y -qq docker.io
      ;;
    centos|rhel|fedora)
      yum install -y -q docker
      ;;
    *)
      echo "[docker] Unsupported OS: $OS"
      exit 1
      ;;
  esac
fi

systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker

if ! docker info >/dev/null 2>&1; then
  echo "[docker] Docker did not start correctly"
  exit 1
fi

echo "[docker] Docker ready"
