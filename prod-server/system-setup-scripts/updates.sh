#!/bin/bash

set -euo pipefail

# --------------------------------------------
# Colors and Styles
# --------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --------------------------------------------
# Functions
# --------------------------------------------

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error_exit() {
    echo -e "${RED}❌ ERROR: $1${NC}"
    exit 1
}

section() {
    echo ""
    echo -e "${YELLOW}========================================"
    echo "     $1"
    echo -e "========================================${NC}"
    echo ""
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    tput civis  # hide cursor
    while kill -0 "$pid" 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r${YELLOW}[%c]${NC} " "${spinstr:i:1}"
            sleep $delay
        done
    done
    printf "\r"
    tput cnorm  # show cursor
}

# --------------------------------------------
# Detect OS and Info
# --------------------------------------------

section "Detecting Operating System"

OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
DISTRO="unknown"

if [ -f /etc/os-release ]; then
    DISTRO_ID=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    DISTRO=$DISTRO_ID
fi

CURRENT_USER=$(whoami)
HOSTNAME=$(hostname)

info "Detected OS: $DISTRO"
info "Current User: $CURRENT_USER"
info "Hostname: $HOSTNAME"

# --------------------------------------------
# Update System Packages
# --------------------------------------------

section "Updating System Packages"

case "$DISTRO" in
    ubuntu|debian)
        info "Updating using apt..."
        sudo apt update -y > /dev/null 2>&1 &
        spinner $!
        sudo apt upgrade -y > /dev/null 2>&1 &
        spinner $!
        ;;
    centos|rhel|fedora|rocky)
        info "Updating using yum/dnf..."
        if command -v dnf &> /dev/null; then
            sudo dnf upgrade -y > /dev/null 2>&1 &
            spinner $!
        else
            sudo yum update -y > /dev/null 2>&1 &
            spinner $!
        fi
        ;;
    amazon)
        info "Updating using amazon-linux-extras..."
        sudo yum update -y > /dev/null 2>&1 &
        spinner $!
        ;;
    *)
        warn "Unsupported Linux distribution: $DISTRO"
        error_exit "Update process cannot continue on this OS."
        ;;
esac

success "System update completed successfully!"