#!/bin/bash

# ------------------------------------------------------------------------------
# System Update and Git Management Script
# Supports: Ubuntu, Amazon Linux, CentOS, RHEL
# ------------------------------------------------------------------------------

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────
log()   { echo -e "\033[1;34m[INFO]\033[0m $1"; }
err()   { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

# ──────────────────────────────────────────────────────────────────────────────
# DETECT OS & PACKAGE MANAGER
# ──────────────────────────────────────────────────────────────────────────────
detect_os() {
  [[ -f /etc/os-release ]] || err "/etc/os-release not found"
  source /etc/os-release

  case "$ID" in
    ubuntu)      OS="ubuntu";      PKG="apt" ;;
    amzn)        OS="amazon";      PKG="yum" ;;
    centos|rhel) OS="$ID";         PKG="yum" ;;
    *)           err "Unsupported OS: $ID" ;;
  esac
}

# ──────────────────────────────────────────────────────────────────────────────
# SYSTEM UPDATE/UPGRADE
# ──────────────────────────────────────────────────────────────────────────────
update_system() {
  log "Updating system packages on $OS..."
  case "$PKG" in
    apt)
      sudo apt update -y || true
      sudo apt upgrade -y || {
        log "Retrying with --fix-missing..."
        sudo apt update -y --fix-missing
        sudo apt upgrade -y
      }
      ;;
    yum)
      sudo yum update -y
      ;;
    dnf)
      sudo dnf upgrade -y
      ;;
    *)
      err "Unsupported package manager: $PKG"
      ;;
  esac
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL ESSENTIAL UTILITIES
# ──────────────────────────────────────────────────────────────────────────────
install_utilities() {
  log "Installing Git, Python, pip, venv, curl, unzip, zip, and pytest..."

  case "$PKG" in
    apt)
      sudo apt install -y git python3 python3-pip python3-venv curl unzip zip python3-pytest
      ;;
    yum|dnf)
      sudo $PKG install -y git python3 python3-pip curl unzip zip python3-pytest
      ;;
    *)
      err "Unsupported package manager for utilities: $PKG"
      ;;
  esac

  # Verify installs
  for cmd in git python3 pip3 curl unzip zip; do
    command -v "$cmd" >/dev/null || err "$cmd installation failed!"
  done

  if ! python3 -m pytest --version >/dev/null 2>&1; then
    err "pytest installation failed or pytest module not found!"
  fi

  log "✅ All essential utilities are installed successfully."
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ──────────────────────────────────────────────────────────────────────────────
log "🔍 Detecting system..."
detect_os

log "📦 Performing system update..."
update_system

log "🧰 Installing utilities..."
install_utilities

log "✅ Update script completed successfully."
exit 0