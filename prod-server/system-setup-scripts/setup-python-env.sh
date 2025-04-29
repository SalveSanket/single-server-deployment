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

if [ -t 1 ]; then trap 'tput cnorm' EXIT; else trap '' EXIT; fi

# --------------------------------------------
# Detecting System Information
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

info "Detected OS: $DISTRO"
info "Current User: $CURRENT_USER"
info "Hostname: $HOSTNAME"

# --------------------------------------------
# Install Python and Pip
# --------------------------------------------
section "Installing Python and Pip"

install_python=false
if ! command -v python3 >/dev/null 2>&1; then
    install_python=true
fi

case "$DISTRO" in
    ubuntu|debian)
        if $install_python; then
            info "Installing python3, pip3, venv..."
            sudo apt-get update -y > /dev/null 2>&1 &
            spinner $!
        fi

        info "Installing python3-venv, python3.10-venv, pip3..."
        sudo apt-get install -y python3 python3-pip python3-venv python3.10-venv > /dev/null 2>&1 &
        spinner $!
        ;;
    centos|rhel|rocky|amzn)
        if $install_python; then
            info "Installing python3 and pip3..."
            sudo yum update -y > /dev/null 2>&1 &
            spinner $!
        fi

        sudo yum install -y python3 python3-pip python3-virtualenv > /dev/null 2>&1 &
        spinner $!
        ;;
    *)
        error_exit "Unsupported Linux distribution: $DISTRO"
        ;;
esac

command -v python3 >/dev/null || error_exit "Python3 installation failed."
command -v pip3 >/dev/null || error_exit "pip3 installation failed."

success "Python3 and Pip3 installation complete."

# --------------------------------------------
# Setup Application Directory
# --------------------------------------------
section "Setting up Project Directory"

APP_DIR="/home/$CURRENT_USER/app"
if [ -d "$APP_DIR" ]; then
    warn "App directory already exists: $APP_DIR"
else
    info "Creating directory: $APP_DIR"
    mkdir -p "$APP_DIR"
    success "Directory created."
fi

cd "$APP_DIR" || error_exit "Failed to enter app directory."

# --------------------------------------------
# Create Python Virtual Environment
# --------------------------------------------
section "Creating Python Virtual Environment"

if [ -d "venv" ]; then
    if [ -f "venv/bin/activate" ]; then
        success "Virtual environment already exists."
    else
        warn "venv directory is invalid. Removing and recreating..."
        rm -rf venv
    fi
fi

if [ ! -d "venv" ]; then
    info "Creating new virtual environment..."
    python3 -m venv venv || error_exit "Failed to create virtual environment."
    success "Virtual environment created."
fi

# --------------------------------------------
# Install Flask inside venv
# --------------------------------------------
section "Installing Flask in Virtual Environment"

if [ ! -f "venv/bin/activate" ]; then
    error_exit "Virtual environment activation script not found. Ensure venv was created successfully."
fi

source venv/bin/activate
if pip list | grep -q Flask; then
    success "Flask already installed in virtualenv."
else
    info "Installing Flask..."
    pip install --upgrade pip > /dev/null 2>&1 &
    spinner $!
    pip install flask > /dev/null 2>&1 &
    spinner $!
    success "Flask installed."
fi
deactivate

# --------------------------------------------
# Create flaskapp.service for systemd
# --------------------------------------------
section "Creating flaskapp.service for systemd"

SERVICE_PATH="/etc/systemd/system/flaskapp.service"

if [ -f "$SERVICE_PATH" ]; then
    success "Systemd service already exists: flaskapp.service"
else
    info "Creating systemd service..."
    cat <<EOF | sudo tee "$SERVICE_PATH" > /dev/null
[Unit]
Description=Flask Web Application
After=network.target

[Service]
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    success "Systemd service created."
fi

# --------------------------------------------
# Start or Restart the Flask Service
# --------------------------------------------
section "Starting or Restarting flaskapp.service"

info "Reloading systemd daemon..."
sudo systemctl daemon-reexec > /dev/null 2>&1 &
spinner $!
sudo systemctl daemon-reload > /dev/null 2>&1 &
spinner $!

info "Enabling flaskapp.service on boot..."
sudo systemctl enable flaskapp.service > /dev/null 2>&1 &
spinner $!

info "Restarting flaskapp.service..."
sudo systemctl restart flaskapp.service > /dev/null 2>&1 &
spinner $!

success "Flask app service is running 🚀"