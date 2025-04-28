#!/bin/bash

set -euo pipefail

# --------------------------------------------
# Color and Output Formatting
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

section() {
    echo ""
    echo -e "\033[1;33m========================================"
    echo "     $1"
    echo -e "========================================\033[0m"
    echo ""
}

# --------------------------------------------
# Spinner for background tasks
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
# Retry Safe Command Execution
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
# Script Execution Starts Here
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
# Install Python and Pip
# --------------------------------------------
section "Installing Python and Pip"

case "$DISTRO" in
    ubuntu|debian)
        info "Updating apt package index..."
        retry_command sudo apt update -y &
        spinner $!
        info "Installing python3, pip3, venv..."
        retry_command sudo apt install -y python3 python3-pip python3-venv &
        spinner $!
        ;;
    centos|rhel|rocky)
        info "Updating yum package index..."
        retry_command sudo yum update -y &
        spinner $!
        info "Installing python3 and pip3..."
        retry_command sudo yum install -y python3 python3-pip &
        spinner $!
        ;;
    amzn)
        info "Updating yum package index..."
        retry_command sudo yum update -y &
        spinner $!
        info "Installing python3..."
        retry_command sudo yum install -y python3 &
        spinner $!
        if ! command -v pip3 &> /dev/null; then
            info "Installing pip3 manually..."
            retry_command sudo python3 -m ensurepip --upgrade &
            spinner $!
        fi
        ;;
    *)
        error_exit "Unsupported Linux distribution: $DISTRO"
        ;;
esac

success "Python3 and Pip3 installation completed."

# --------------------------------------------
# Setup Project Directory
# --------------------------------------------
section "Setting up Project Directory"

APP_DIR="/home/$CURRENT_USER/app"

info "Creating application directory at: $APP_DIR"
mkdir -p "$APP_DIR" || error_exit "Failed to create application directory."
success "Directory created: $APP_DIR"

cd "$APP_DIR" || error_exit "Failed to move into application directory."
success "Moved into directory: $APP_DIR"

# --------------------------------------------
# Create Python Virtual Environment
# --------------------------------------------
section "Creating Python Virtual Environment"

info "Creating virtual environment 'venv/'"
python3 -m venv venv || error_exit "Failed to create virtual environment."
success "Virtual environment created at $APP_DIR/venv"

# --------------------------------------------
# Install Flask inside venv
# --------------------------------------------
section "Installing Flask in Virtual Environment"

info "Activating virtual environment and installing Flask..."
source venv/bin/activate
retry_command pip install --upgrade pip
retry_command pip install flask
deactivate
success "Flask installed successfully inside virtual environment."

# --------------------------------------------
# Create Sample app.py (if not exists)
# --------------------------------------------
section "Creating Sample Flask Application"

if [ ! -f "$APP_DIR/app.py" ]; then
    info "Creating sample app.py..."
    cat <<EOF > app.py
from flask import Flask
app = Flask(__name__)

@app.route("/")
def home():
    return "Hello, Flask World!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF
    success "Sample app.py created."
else
    warn "app.py already exists, skipping creation."
fi

# --------------------------------------------
# Create systemd service for Flask app
# --------------------------------------------
section "Creating flaskapp.service for systemd"

cat <<EOF | sudo tee /etc/systemd/system/flaskapp.service
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

success "flaskapp.service created at /etc/systemd/system/"

# --------------------------------------------
# Reload systemd and start the service
# --------------------------------------------
section "Starting flaskapp.service"

info "Reloading systemd daemon..."
retry_command sudo systemctl daemon-reload &
spinner $!

info "Enabling flaskapp.service to start on boot..."
retry_command sudo systemctl enable flaskapp.service &
spinner $!

info "Starting flaskapp.service now..."
retry_command sudo systemctl start flaskapp.service &
spinner $!

success "Flask app service is up and running."

# --------------------------------------------
# Final Success
# --------------------------------------------
section "Deployment Completed Successfully 🚀"

success "✅ Python3 and Pip3 installed."
success "✅ Flask installed."
success "✅ Application created at $APP_DIR."
success "✅ Systemd service running: flaskapp.service"

echo ""
info "You can check your app at: http://<your-server-ip>:5000"
echo ""