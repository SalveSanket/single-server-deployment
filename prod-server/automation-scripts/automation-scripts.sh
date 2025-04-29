#!/bin/bash

set -e

# --------------------------------------------
# Color Output Functions
# --------------------------------------------
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error_exit() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

# --------------------------------------------
# Spinner Function
# --------------------------------------------
spinner() {
    local pid=$1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    tput civis
    while kill -0 "$pid" 2>/dev/null; do
        for i in $(seq 0 $((${#spinstr} - 1))); do
            printf "\r [%c]  " "${spinstr:i:1}"
            sleep 0.1
        done
    done
    tput cnorm
    wait "$pid"
    return $?
}

trap 'tput cnorm' EXIT

# --------------------------------------------
# Retry Function
# --------------------------------------------
retry_command() {
    local n=0 max=3 delay=2 cmd="$*"
    until [ $n -ge $max ]; do
        eval "$cmd" && break
        n=$((n+1))
        warn "Retry $n/$max in $delay seconds..."
        sleep $delay
    done
    [ $n -eq $max ] && error_exit "Command failed: $cmd"
}

# --------------------------------------------
# Confirmations
# --------------------------------------------
AUTO_CONFIRM=false
if [[ "$1" == "--yes" ]]; then AUTO_CONFIRM=true; fi

ask_confirmation() {
    if $AUTO_CONFIRM; then
        info "Auto-confirm mode enabled. Proceeding..."
    else
        read -r -p "$1 (yes/no): " response
        [[ "$response" != "yes" ]] && {
            warn "User cancelled operation."
            exit 0
        }
    fi
}

# --------------------------------------------
# Define Paths
# --------------------------------------------
info "Resolving project structure..."
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/prod-server/terraform"
SCRIPTS_DIR="$ROOT_DIR/prod-server/system-setup-scripts"
REMOTE_DIR_NAME="system-setup-scripts"
PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH:-$HOME/.ssh/ProdKey}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-$HOME/.ssh/ProdKey.pub}"

success "Project root: $ROOT_DIR"
success "Terraform dir: $TERRAFORM_DIR"

# --------------------------------------------
# Check Requirements
# --------------------------------------------
info "Checking prerequisites..."
for path in "$TERRAFORM_DIR" "$SCRIPTS_DIR" "$PRIVATE_KEY_PATH" "$PUBLIC_KEY_PATH"; do
    [ -e "$path" ] || error_exit "$(basename "$path") not found at $path"
done
for cmd in terraform ssh scp; do
    command -v "$cmd" >/dev/null || error_exit "$cmd is not installed"
done
success "All prerequisites met."

# --------------------------------------------
# Fetch Terraform Outputs
# --------------------------------------------
info "Fetching Terraform values..."
PROD_SERVER_IP=$(terraform -chdir="$TERRAFORM_DIR" output -raw prodserver_public_ip)
DEFAULT_SSH_USER=$(terraform -chdir="$TERRAFORM_DIR" output -raw default_ssh_user)

[ -z "$PROD_SERVER_IP" ] && error_exit "Missing prodserver_public_ip"
[ -z "$DEFAULT_SSH_USER" ] && error_exit "Missing default_ssh_user"
success "Server IP: $PROD_SERVER_IP"
success "SSH User : $DEFAULT_SSH_USER"

# --------------------------------------------
# Show Files to Be Copied
# --------------------------------------------
info "Files to be copied to ~/system-setup-scripts:"
for file in "$SCRIPTS_DIR"/*; do echo "  - $(basename "$file")"; done
echo ""
ask_confirmation "Proceed with copying files?"

# --------------------------------------------
# Create Remote Directory
# --------------------------------------------
info "Creating remote directory..."
ssh -i "$PRIVATE_KEY_PATH" -o StrictHostKeyChecking=accept-new "$DEFAULT_SSH_USER@$PROD_SERVER_IP" "mkdir -p ~/$REMOTE_DIR_NAME" &
spinner $!
success "Remote directory created."

# --------------------------------------------
# Copy Files to Remote
# --------------------------------------------
info "Copying files to remote server..."
scp -i "$PRIVATE_KEY_PATH" -o StrictHostKeyChecking=accept-new -r "$SCRIPTS_DIR/"* "$DEFAULT_SSH_USER@$PROD_SERVER_IP:~/$REMOTE_DIR_NAME/" &
spinner $!
success "Files copied successfully."

# --------------------------------------------
# Run Scripts on Remote Server
# --------------------------------------------
info "Running scripts on remote server..."

ssh -T -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" <<'EOF'
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
    echo "[INFO] Running $script..."
    ./"$script"
  done

  echo "[SUCCESS] All scripts executed successfully."
EOF

success "Remote script execution completed."
success "All automation scripts executed successfully."