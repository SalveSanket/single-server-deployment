#!/bin/bash

set -euo pipefail

# --------------------------------------------
# Color functions for output
# --------------------------------------------
info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

warn() {
    echo -e "\033[1;33m[WARN]\033[0m $1"
}

error_exit() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
    exit 1
}

# --------------------------------------------
# Spinner function
# --------------------------------------------
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    tput civis
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    tput cnorm
    wait "$pid"
    return $?
}

trap 'tput cnorm' EXIT

# --------------------------------------------
# Section header
# --------------------------------------------
section() {
    echo ""
    echo -e "\033[1;33m========================================"
    echo "     $1"
    echo -e "========================================\033[0m"
    echo ""
}

# --------------------------------------------
# Retry function
# --------------------------------------------
retry_command() {
    local retries=3
    local count=0
    until "$@"; do
        exit_code=$?
        wait_time=$((2 ** count))
        if [ $count -lt $retries ]; then
            warn "Command failed with exit code $exit_code. Retrying in $wait_time seconds..."
            sleep $wait_time
            ((count++))
        else
            error_exit "Command failed after $retries attempts."
        fi
    done
}

# --------------------------------------------
# Start of Script
# --------------------------------------------

section "Detecting System Information"

OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
DISTRO="unknown"

if [ -f /etc/os-release ]; then
    DISTRO_ID=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    DISTRO=$DISTRO_ID
fi

CURRENT_USER=$(whoami)
HOSTNAME=$(hostname)

info "Detected OS         : $DISTRO"
info "Current User        : $CURRENT_USER"
info "Hostname            : $HOSTNAME"

# --------------------------------------------
# Install Python3 and Pip3 based on OS
# --------------------------------------------
section "Installing Python and Pip"

case "$DISTRO" in
    ubuntu|debian)
        info "Updating apt package index..."
        retry_command bash -c "sudo apt update -y &"
        spinner $!

        info "Installing python3 and pip3..."
        retry_command bash -c "sudo apt install -y python3 python3-pip &"
        spinner $!
        ;;
    centos|rhel|rocky)
        info "Updating yum package index..."
        retry_command bash -c "sudo yum update -y &"
        spinner $!

        info "Installing python3 and pip3..."
        retry_command bash -c "sudo yum install -y python3 python3-pip &"
        spinner $!
        ;;
    amzn)
        info "Updating yum package index..."
        retry_command bash -c "sudo yum update -y &"
        spinner $!

        info "Installing python3..."
        retry_command bash -c "sudo yum install -y python3 &"
        spinner $!

        if ! command -v pip3 &> /dev/null; then
            info "Installing pip3 manually..."
            retry_command bash -c "sudo python3 -m ensurepip --upgrade &"
            spinner $!
        fi
        ;;
    *)
        error_exit "Unsupported Linux distribution: $DISTRO"
        ;;
esac

# --------------------------------------------
# Final checks
# --------------------------------------------

section "Verifying Installation"

PYTHON_VERSION=$(python3 --version 2>/dev/null || echo "Not Found")
PIP_VERSION=$(pip3 --version 2>/dev/null || echo "Not Found")

if [[ "$PYTHON_VERSION" == "Not Found" ]]; then
    error_exit "Python3 installation failed!"
else
    success "Python3 Installed: $PYTHON_VERSION"
fi

if [[ "$PIP_VERSION" == "Not Found" ]]; then
    error_exit "Pip3 installation failed!"
else
    success "Pip3 Installed: $PIP_VERSION"
fi

section "Python Environment Setup Completed Successfully 🚀"
success "System is ready with Python3 and Pip3!"