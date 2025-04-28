#!/usr/bin/env bash

# Setup Python environment and Flask app
# (Production-ready with color-coded output, spinner animations, and retry logic)

# Define color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'  # No Color

# Show a spinner while a process id is running
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr="|/-\\"
    while [ -d /proc/$pid ]; do
        local char=${spinstr:0:1}
        printf " [%c]  " "$char"
        spinstr="${spinstr:1}$char"
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error:${NC} Please run as root or with sudo"
    exit 1
fi

# Determine application user (use SUDO_USER if available)
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    APP_USER="$SUDO_USER"
else
    APP_USER="$(id -un)"
fi

APP_HOME=$(eval echo "~$APP_USER")
APP_DIR="$APP_HOME/app"

# Update package lists (with retry on failure)
echo -ne "${YELLOW}Updating apt repositories...${NC}"
retry=0
until [ $retry -ge 3 ]; do
    apt-get update -qq > /dev/null 2>&1 & pid=$!
    spinner $pid
    if wait $pid; then
        echo -e "${GREEN} done${NC}"
        break
    else
        ((retry++))
        if [ $retry -ge 3 ]; then
            echo -e "${RED} failed after ${retry} attempts${NC}"
            exit 1
        fi
        echo -e "\n${YELLOW}Retrying apt update (attempt $((retry+1)))...${NC}"
        sleep 2
    fi
done

# Install Python3, pip3, and venv (with retry on failure)
echo -ne "${YELLOW}Installing Python3, pip3, and python3-venv...${NC}"
retry=0
until [ $retry -ge 3 ]; do
    apt-get install -y python3 python3-pip python3-venv -qq > /dev/null 2>&1 & pid=$!
    spinner $pid
    if wait $pid; then
        echo -e "${GREEN} done${NC}"
        break
    else
        ((retry++))
        if [ $retry -ge 3 ]; then
            echo -e "${RED} failed after ${retry} attempts${NC}"
            exit 1
        fi
        echo -e "\n${YELLOW}Retrying install (attempt $((retry+1)))...${NC}"
        sleep 2
    fi
done

# Create application directory
echo -ne "${YELLOW}Creating application directory at ${APP_DIR}...${NC}"
mkdir -p "$APP_DIR"
chown "$APP_USER":"$APP_USER" "$APP_DIR"
echo -e "${GREEN} done${NC}"

# Create Python virtual environment
echo -ne "${YELLOW}Creating Python virtual environment...${NC}"
python3 -m venv "$APP_DIR/venv"
if [ $? -ne 0 ]; then
    echo -e "${RED} failed to create virtual environment${NC}"
    exit 1
fi
echo -e "${GREEN} done${NC}"

# Activate virtual environment and install Flask
echo -ne "${YELLOW}Activating virtual environment and installing Flask...${NC}"
# shellcheck disable=SC1090
source "$APP_DIR/venv/bin/activate"
pip install --upgrade pip >/dev/null 2>&1
pip install Flask >/dev/null 2>&1
deactivate
echo -e "${GREEN} done${NC}"

# Create systemd service file for Flask app
echo -ne "${YELLOW}Creating flaskapp.service systemd unit...${NC}"
cat << EOF > /etc/systemd/system/flaskapp.service
[Unit]
Description=Flask Application Service
After=network.target

[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/app.py

[Install]
WantedBy=multi-user.target
EOF
echo -e "${GREEN} done${NC}"

# Reload systemd and start Flask service
echo -ne "${YELLOW}Reloading systemd and starting Flask service...${NC}"
systemctl daemon-reload
systemctl enable flaskapp.service
systemctl start flaskapp.service
echo -e "${GREEN} done${NC}"

echo -e "${GREEN}Flask application setup complete.${NC}"