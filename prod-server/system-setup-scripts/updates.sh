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
# Output Functions
# --------------------------------------------
info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
error_exit() { echo -e "${RED}❌ ERROR: $1${NC}" >&2; exit 1; }

section() {
    echo ""
    echo -e "${YELLOW}========================================"
    echo "     $1"
    echo -e "========================================${NC}"
    echo ""
}

# --------------------------------------------
# Spinner with safe terminal check
# --------------------------------------------
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    if [ -t 1 ]; then tput civis; fi
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r [%c] " "${spinstr:i++%${#spinstr}:1}"
        sleep $delay
    done
    if [ -t 1 ]; then tput cnorm; fi
    wait "$pid"
    return $?
}

# Hide cursor on exit only in terminal
if [ -t 1 ]; then
    trap 'tput cnorm' EXIT
else
    trap '' EXIT
fi

# --------------------------------------------
# Detect OS Info
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
        export DEBIAN_FRONTEND=noninteractive
        export NEEDRESTART_MODE=a
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
    amzn)
        info "Updating using amazon-linux..."
        sudo yum update -y > /dev/null 2>&1 &
        spinner $!
        ;;
    *)
        warn "Unsupported Linux distribution: $DISTRO"
        error_exit "Update process cannot continue on this OS."
        ;;
esac

success "System update completed successfully!"
