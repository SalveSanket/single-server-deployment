#!/bin/bash

# ------------------------------------------
# Production-Ready Script to Copy System Setup Scripts
# ------------------------------------------
# This script fetches Terraform outputs, copies system-setup-scripts 
# to the remote instance, ensures all scripts are executable, runs updates.sh first,
# then executes all other scripts.
# ------------------------------------------

set -e  # Exit on error

# --------------------------------------------
# Color and Output Functions
# --------------------------------------------
info()    { printf "\033[1;34m[INFO]\033[0m %s\n" "$1"; }
success() { printf "\033[1;32m[SUCCESS]\033[0m %s\n" "$1"; }
warn()    { printf "\033[1;33m[WARNING]\033[0m %s\n" "$1"; }
error_exit() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1"; exit 1; }

section() {
  printf "\n\033[1;36m%s\033[0m\n%s\n" "$1" "$(printf '%.0s-' $(seq 1 ${#1}))"
}

# --------------------------------------------
# Spinner Function
# --------------------------------------------
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  tput civis
  while kill -0 "$pid" 2>/dev/null; do
    for i in $(seq 0 $((${#spinstr} - 1))); do
      printf "\r [%c]  " "${spinstr:i:1}"
      sleep $delay
    done
  done
  tput cnorm
  wait "$pid"
  return $?
}

trap 'tput cnorm' EXIT

# --------------------------------------------
# Retry Command Function
# --------------------------------------------
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

# --------------------------------------------
# Support for --yes (auto-confirm mode)
# --------------------------------------------
AUTO_CONFIRM=false
if [[ "${1:-}" == "--yes" ]]; then
  AUTO_CONFIRM=true
fi

# --------------------------------------------
# Start Execution
# --------------------------------------------
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/jenkins-server/terraform"
SCRIPTS_DIR="$ROOT_DIR/jenkins-server/system-setup-scripts"
REMOTE_DIR_NAME="system-setup-scripts"

# Ensure Terraform and scripts directories exist
[ ! -d "$TERRAFORM_DIR" ] && error_exit "Terraform directory not found: $TERRAFORM_DIR"
[ ! -d "$SCRIPTS_DIR" ] && error_exit "System setup scripts directory not found: $SCRIPTS_DIR"

# --------------------------------------------
# Fetch Terraform Outputs
# --------------------------------------------
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

# --------------------------------------------
# Prepare to Copy Scripts
# --------------------------------------------
section "Remote server info"
info "Connecting to: $SSH_USER@$PUBLIC_IP"
info "Copying from: $SCRIPTS_DIR"

section "Contents to be copied"
find "$SCRIPTS_DIR" -type f | sed "s|$ROOT_DIR/||"

echo ""

if [[ "$AUTO_CONFIRM" == true ]]; then
  info "Auto-confirm enabled. Proceeding with file copy..."
else
  read -p "Proceed with copying the above files to the remote server? (yes/no): " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && { info "Operation cancelled."; exit 0; }
fi

# --------------------------------------------
# Copy Scripts to Remote Server
# --------------------------------------------
section "Copying directory to remote server"

retry_command ssh -i "$PRIVATE_KEY" "$SSH_USER@$PUBLIC_IP" "rm -rf ~/$REMOTE_DIR_NAME && mkdir -p ~/$REMOTE_DIR_NAME" &
spinner $!

retry_command scp -i "$PRIVATE_KEY" -r "$SCRIPTS_DIR" "$SSH_USER@$PUBLIC_IP:~/" &
spinner $!

# --------------------------------------------
# Execute Scripts on Remote Server
# --------------------------------------------
section "Executing scripts on remote server"

ssh -T -i "$PRIVATE_KEY" "$SSH_USER@$PUBLIC_IP" <<'REMOTE_CMDS'
  set -e
  cd ~/system-setup-scripts

  if [ -f "updates.sh" ]; then
    chmod +x updates.sh
    echo "[INFO] Running updates.sh..."
    ./updates.sh
  else
    echo "[WARNING] updates.sh not found. Skipping..."
  fi

  for script in $(ls -1 *.sh 2>/dev/null | grep -v '^updates.sh$'); do
    chmod +x "$script"
    echo "[INFO] Executing $script..."
    ./"$script"
  done
REMOTE_CMDS

# --------------------------------------------
# Final Success Message
# --------------------------------------------
success "Successfully copied '$REMOTE_DIR_NAME' and executed scripts on $SSH_USER@$PUBLIC_IP"
success "All scripts executed successfully."
success "Jenkins server setup completed."