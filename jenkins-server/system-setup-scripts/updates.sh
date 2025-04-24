#!/bin/bash

# ------------------------------------------------------------------------------
# System Update and Git Management Script
# Supports: Ubuntu, Amazon Linux, CentOS, RHEL
# ------------------------------------------------------------------------------

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────
log()   { echo "[INFO] $1"; }
err()   { echo "[ERROR] $1" >&2; exit 1; }

# ──────────────────────────────────────────────────────────────────────────────
# DETECT OS & PACKAGE MANAGER
# ──────────────────────────────────────────────────────────────────────────────
detect_os() {
  [[ -f /etc/os-release ]] || err "/etc/os-release not found"
  source /etc/os-release

  case "$ID" in
    ubuntu)
      OS="ubuntu"
      PKG="apt"
      ;;
    amzn)
      [[ "$VERSION_ID" =~ ^2 ]] && OS="amazon2" || OS="amazon2023"
      PKG="yum"
      ;;
    centos|rhel)
      OS="$ID"
      PKG="yum"
      ;;
    *)
      err "Unsupported OS: $ID"
      ;;
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
      if ! sudo apt upgrade -y; then
        log "Encountered package fetch errors, retrying with --fix-missing..."
        sudo apt update -y --fix-missing
        sudo apt upgrade -y
      fi
      ;;
    yum)
      sudo yum update -y && sudo yum upgrade -y
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
# INSTALL OR UPDATE GIT
# ──────────────────────────────────────────────────────────────────────────────
install_or_update_git() {
  if command -v git &>/dev/null; then
    log "Git is already installed: version $(git --version)"
    case "$PKG" in
      apt)
        sudo apt install -y git
        ;;
      yum|dnf)
        sudo $PKG install -y git
        ;;
    esac
    log "✅ Git has been updated to: $(git --version)"
  else
    log "Git is not installed. Installing..."
    case "$PKG" in
      apt)
        sudo apt install -y git
        ;;
      yum|dnf)
        sudo $PKG install -y git
        ;;
    esac
    log "✅ Git installation complete: $(git --version)"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ──────────────────────────────────────────────────────────────────────────────
log "🔍 Detecting system..."
detect_os

log "📦 Performing system update..."
update_system

log "🐙 Checking Git installation..."
install_or_update_git

log "✅ Update script completed successfully."