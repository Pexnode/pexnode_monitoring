#!/bin/bash
# Install Docker on host (called by enroll-host.sh)

set -e

echo "Installing Docker..."

# Detect OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  echo "Cannot detect OS"
  exit 1
fi

case "$OS" in
  ubuntu|debian)
    apt-get update -qq
    apt-get install -y -qq docker.io
    systemctl enable docker
    systemctl start docker
    ;;
  centos|rhel|fedora)
    yum install -y -q docker
    systemctl enable docker
    systemctl start docker
    ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

echo "Docker installed"
