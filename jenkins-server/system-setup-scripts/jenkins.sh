#!/bin/bash

# ------------------------------------------------------------------------------
# Universal Jenkins Installation Script for EC2 Linux Distributions
# ------------------------------------------------------------------------------

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION VARIABLES
# ──────────────────────────────────────────────────────────────────────────────
JENKINS_REPO_URL="https://pkg.jenkins.io/redhat-stable/jenkins.repo"
JENKINS_KEY_URL="https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key"
INITIAL_ADMIN_PASSWORD_PATH="/var/lib/jenkins/secrets/initialAdminPassword"

# ──────────────────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────
log() { echo "[INFO] $1"; }
err() { echo "[ERROR] $1" >&2; exit 1; }

# ──────────────────────────────────────────────────────────────────────────────
# OS & PACKAGE MANAGER DETECTION
# ──────────────────────────────────────────────────────────────────────────────
detect_os() {
  [[ -f /etc/os-release ]] || err "/etc/os-release not found"
  source /etc/os-release

  case "$ID" in
    amzn)
      [[ "$VERSION_ID" =~ ^2 ]] && OS="amazon2" || OS="amazon2023"
      PKG="yum"
      ;;
    ubuntu)
      OS="ubuntu"
      PKG="apt"
      ;;
    centos|rhel)
      OS="centos"
      PKG="yum"
      ;;
    *) err "Unsupported OS: $ID" ;;
  esac
}

# ──────────────────────────────────────────────────────────────────────────────
# DETECT DEFAULT EC2 USER
# ──────────────────────────────────────────────────────────────────────────────
detect_user() {
  for user in ec2-user ubuntu centos admin; do
    id "$user" &>/dev/null && DEFAULT_USER="$user" && return
  done
  err "No known default EC2 user found"
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL JAVA & JENKINS
# ──────────────────────────────────────────────────────────────────────────────
install_jenkins() {
  case "$PKG" in
    yum|dnf)
      log "Updating packages..."
      sudo $PKG update -y
      log "Installing Amazon Corretto 17..."
      sudo $PKG install -y java-17-amazon-corretto

      log "Adding Jenkins repo and key..."
      sudo wget -O /etc/yum.repos.d/jenkins.repo "$JENKINS_REPO_URL"
      sudo rpm --import "$JENKINS_KEY_URL"

      log "Installing Jenkins..."
      sudo $PKG install -y jenkins
      ;;
    apt)
      log "Updating packages..."
      sudo apt update -y && sudo apt upgrade -y

      log "Installing OpenJDK 17..."
      sudo apt install -y openjdk-17-jdk

      log "Adding Jenkins repo and key (secure for Ubuntu)..."
      curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | \
        gpg --dearmor | sudo tee /usr/share/keyrings/jenkins-keyring.gpg > /dev/null

      echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" | \
        sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

      sudo apt update
      log "Installing Jenkins..."
      sudo apt install -y jenkins
      ;;
    *) err "Unsupported package manager: $PKG" ;;
  esac

  log "Enabling Jenkins service..."
  sudo systemctl enable jenkins

  log "Starting Jenkins service..."
  sudo systemctl start jenkins

  sudo systemctl status jenkins --no-pager
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ──────────────────────────────────────────────────────────────────────────────
log "🔍 Detecting system configuration..."
detect_os
detect_user

log "Detected OS: $OS"
log "Detected EC2 user: $DEFAULT_USER"

install_jenkins

log "✅ Jenkins installation complete."
log "🔐 Initial admin password is located at:"
echo "$INITIAL_ADMIN_PASSWORD_PATH"