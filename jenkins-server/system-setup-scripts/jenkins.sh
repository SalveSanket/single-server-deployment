#!/bin/bash

# ------------------------------------------------------------------------------
# Jenkins Installation Script for EC2 Linux Distributions (Ubuntu, Amazon, CentOS, RHEL)
# ------------------------------------------------------------------------------

set -euo pipefail

# Jenkins Repo Configuration
JENKINS_REPO_URL="https://pkg.jenkins.io/redhat-stable/jenkins.repo"
JENKINS_KEY_URL="https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key"
INITIAL_ADMIN_PASSWORD_PATH="/var/lib/jenkins/secrets/initialAdminPassword"

# Logging functions
log() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

# Detect OS type and package manager
detect_os() {
  [[ -f /etc/os-release ]] || err "/etc/os-release not found"
  source /etc/os-release

  case "$ID" in
    ubuntu) OS="ubuntu"; PKG="apt" ;;
    amzn)   OS="amazon"; PKG="yum" ;;
    centos|rhel) OS="$ID"; PKG="yum" ;;
    *) err "Unsupported OS: $ID" ;;
  esac
}

# Detect default EC2 user
detect_user() {
  for user in ec2-user ubuntu centos admin; do
    if id "$user" &>/dev/null; then
      DEFAULT_USER="$user"
      return
    fi
  done
  err "No known default EC2 user found"
}

# Install Java and Jenkins
install_jenkins() {
  log "Updating system packages..."
  sudo $PKG update -y || true

  # Install Java 17 if not already present
  if ! java -version 2>&1 | grep -q '"17'; then
    log "Installing Java 17..."
    case "$PKG" in
      apt) sudo apt install -y openjdk-17-jdk ;;
      yum) sudo yum install -y java-17-amazon-corretto ;;
    esac
  else
    log "Java 17 is already installed."
  fi

  # Install Jenkins if not already installed
  if ! systemctl list-units --all | grep -q jenkins.service; then
    log "Installing Jenkins..."

    if [ "$PKG" = "apt" ]; then
      curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | gpg --dearmor | sudo tee /usr/share/keyrings/jenkins-keyring.gpg > /dev/null
      echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" | \
        sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
      sudo apt update
      sudo apt install -y jenkins
    else
      sudo wget -O /etc/yum.repos.d/jenkins.repo "$JENKINS_REPO_URL"
      sudo rpm --import "$JENKINS_KEY_URL"
      sudo $PKG install -y jenkins
    fi
  else
    log "Jenkins is already installed."
  fi

  log "Enabling and starting Jenkins service..."
  sudo systemctl enable jenkins
  sudo systemctl start jenkins
  sudo systemctl status jenkins --no-pager || true
}

# Main
log "🔍 Detecting system configuration..."
detect_os
detect_user
log "Detected OS: $OS"
log "Detected default user: $DEFAULT_USER"

install_jenkins

log "✅ Jenkins installation completed."
log "🔐 Initial admin password located at:"
echo "$INITIAL_ADMIN_PASSWORD_PATH"