#!/bin/bash

# ------------------------------------------
# Production-Ready Script to Copy System Setup Scripts
# ------------------------------------------
# This script locates Terraform outputs for an AWS EC2 instance,
# copies the system-setup-scripts directory to the remote instance,
# ensures all scripts are executable, runs updates.sh first (if present),
# and then runs all remaining .sh scripts in order.
# ------------------------------------------

set -e  # Exit on error

# Color functions
info()    { printf "\033[1;34m[INFO]\033[0m %s\n" "$1"; }
success() { printf "\033[1;32m[SUCCESS]\033[0m %s\n" "$1"; }
warn()    { printf "\033[1;33m[WARNING]\033[0m %s\n" "$1"; }
error_exit() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1"; exit 1; }

# Section header
section() {
  printf "\n\033[1;36m%s\033[0m\n%s\n" "$1" "$(printf '%.0s-' $(seq 1 ${#1}))"
}

# Spinner function for background jobs
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "       \b\b\b\b\b\b"
}

# Retry command function
retry_command() {
  local n=0
  local max=3
  local delay=2
  local cmd="$*"
  until [ $n -ge $max ]
  do
    eval "$cmd" && break
    n=$((n+1))
    warn "Command failed. Retry $n/$max in $delay seconds..."
    sleep $delay
  done
  if [ $n -eq $max ]; then
    error_exit "Command failed after $max attempts: $cmd"
  fi
}

# Resolve project root (assuming this script lives in /jenkins-server/automation-scripts/)
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/jenkins-server/terraform"
SCRIPTS_DIR="$ROOT_DIR/jenkins-server/system-setup-scripts"
REMOTE_DIR_NAME="system-setup-scripts"

# Check if Terraform and scripts directories exist
[ ! -d "$TERRAFORM_DIR" ] && error_exit "Terraform directory not found: $TERRAFORM_DIR"
[ ! -d "$SCRIPTS_DIR" ] && error_exit "System setup scripts directory not found: $SCRIPTS_DIR"

section "Fetching Terraform outputs"
cd "$TERRAFORM_DIR"
retry_command terraform output -raw jenkins_instance_public_ip > /tmp/public_ip.tmp &
spinner $!
PUBLIC_IP=$(cat /tmp/public_ip.tmp)
retry_command terraform output -raw default_ec2_username > /tmp/ssh_user.tmp &
spinner $!
SSH_USER=$(cat /tmp/ssh_user.tmp)
retry_command terraform output -raw private_key_file > /tmp/private_key.tmp &
spinner $!
PRIVATE_KEY=$(cat /tmp/private_key.tmp)
rm -f /tmp/public_ip.tmp /tmp/ssh_user.tmp /tmp/private_key.tmp

if [[ -z "$PUBLIC_IP" || -z "$SSH_USER" || -z "$PRIVATE_KEY" ]]; then
  error_exit "One or more Terraform outputs are missing."
fi

section "Remote server info"
info "Connecting to: $SSH_USER@$PUBLIC_IP"
info "Copying from: $SCRIPTS_DIR"

section "Contents to be copied"
find "$SCRIPTS_DIR" -type f | sed "s|$ROOT_DIR/||"

echo ""
read -p "Proceed with copying the above files to the remote server? (yes/no): " CONFIRM
[[ "$CONFIRM" != "yes" ]] && { info "Operation cancelled."; exit 0; }

section "Copying directory to remote server"
retry_command ssh -i "$PRIVATE_KEY" "$SSH_USER@$PUBLIC_IP" "rm -rf ~/$REMOTE_DIR_NAME && mkdir -p ~/$REMOTE_DIR_NAME" &
spinner $!
retry_command scp -i "$PRIVATE_KEY" -r "$SCRIPTS_DIR" "$SSH_USER@$PUBLIC_IP:~/" &
spinner $!

section "Executing scripts on remote server"
retry_command ssh -i "$PRIVATE_KEY" "$SSH_USER@$PUBLIC_IP" bash <<EOF
  set -e
  cd ~/$REMOTE_DIR_NAME

  if [ -f "updates.sh" ]; then
    chmod +x updates.sh
    echo "[INFO] Running updates.sh..."
    ./updates.sh
  else
    echo "[WARNING] updates.sh not found. Skipping..."
  fi

  for script in \$(ls -1 *.sh 2>/dev/null | grep -v '^updates.sh$'); do
    chmod +x "\$script"
    echo "[INFO] Executing \$script..."
    "./\$script"
  done
EOF &
spinner $!

echo ""
success "Successfully copied '$REMOTE_DIR_NAME' and executed scripts on $SSH_USER@$PUBLIC_IP"