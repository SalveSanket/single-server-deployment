#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

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
# Confirmations and Checks
# --------------------------------------------
check_exists() {
    if [ ! -e "$1" ]; then
        error_exit "$2 not found at $1!"
    fi
}

ask_confirmation() {
    read -r -p "$1 (yes/no): " response
    if [[ "$response" != "yes" ]]; then
        warn "Operation cancelled by the user."
        exit 0
    fi
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
# Remote command execution
# --------------------------------------------
run_remote_command() {
    ssh -tt -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" "bash -c '
        set -e
        cd ~/$REMOTE_DIR_NAME
        echo -e \"[INFO] Changed directory to ~/$REMOTE_DIR_NAME\"

        chmod +x *.sh 2>/dev/null || echo -e \"[WARN] No .sh files found to make executable.\"
        echo -e \"[SUCCESS] Made all .sh files executable.\"

        if [ -f updates.sh ]; then
            echo -e \"[INFO] Running updates.sh...\"
            ./updates.sh
            echo -e \"[SUCCESS] Finished running updates.sh.\"
        else
            echo -e \"[WARN] updates.sh not found, skipping.\"
        fi

        for script in *.sh; do
            if [ \"\$script\" != \"updates.sh\" ] && [ -x \"\$script\" ]; then
                echo -e \"[INFO] Running \$script...\"
                ./\$script
                echo -e \"[SUCCESS] Finished running \$script.\"
            fi
        done

        echo -e \"[INFO] All scripts executed. Exiting remote session...\"
        exit 0
    '"
}

# --------------------------------------------
# Start of Script Execution
# --------------------------------------------
echo "------------------------"
info "Resolving project root directory..."
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
success "Project root directory resolved to $ROOT_DIR"

echo "------------------------"
info "Defining paths..."
TERRAFORM_DIR="$ROOT_DIR/prod-server/terraform"
SYSTEM_SETUP_DIR="$ROOT_DIR/prod-server/system-setup-scripts"
REMOTE_DIR_NAME="system-setup-scripts"
PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH:-$HOME/.ssh/ProdKey}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-$HOME/.ssh/ProdKey.pub}"
success "Paths defined."

echo "------------------------"
info "Checking prerequisites..."
for path in "$TERRAFORM_DIR" "$SYSTEM_SETUP_DIR" "$PRIVATE_KEY_PATH" "$PUBLIC_KEY_PATH"; do
    check_exists "$path" "$(basename "$path")"
done

for cmd in terraform scp ssh; do
    command -v "$cmd" >/dev/null 2>&1 || error_exit "$cmd command not found. Please install it."
done
success "All prerequisites are met."

echo "------------------------"
info "Fetching Terraform output values..."
PROD_SERVER_IP=$(terraform -chdir="$TERRAFORM_DIR" output -raw prodserver_public_ip)
PROD_SERVER_URL=$(terraform -chdir="$TERRAFORM_DIR" output -raw prodserver_url)
DEFAULT_SSH_USER=$(terraform -chdir="$TERRAFORM_DIR" output -raw default_ssh_user)

[ -z "$PROD_SERVER_IP" ] && error_exit "prodserver_public_ip output is missing!"
[ -z "$DEFAULT_SSH_USER" ] && error_exit "default_ssh_user output is missing!"
success "Terraform output values fetched."

echo "------------------------"
info "The following files from '$SYSTEM_SETUP_DIR' will be copied to the remote server under the home directory (~/$REMOTE_DIR_NAME):"
echo ""
for file in "$SYSTEM_SETUP_DIR"/*; do
    echo "  - $(basename "$file")"
done
echo ""

ask_confirmation "Proceed with copying files?"

# --------------------------------------------
# Prepare remote directory
# --------------------------------------------
echo "------------------------"
info "Ensuring remote directory ~/$REMOTE_DIR_NAME exists..."
ssh -i "$PRIVATE_KEY_PATH" -o StrictHostKeyChecking=accept-new "$DEFAULT_SSH_USER@$PROD_SERVER_IP" "mkdir -p ~/$REMOTE_DIR_NAME" &
pid=$!
spinner $pid || error_exit "Failed to create directory on remote server."
success "Remote directory ensured."

# --------------------------------------------
# Copy files
# --------------------------------------------
echo "------------------------"
info "Copying files to ~$REMOTE_DIR_NAME on remote server..."
scp -i "$PRIVATE_KEY_PATH" -o StrictHostKeyChecking=accept-new -r "$SYSTEM_SETUP_DIR/"* "$DEFAULT_SSH_USER@$PROD_SERVER_IP:~/$REMOTE_DIR_NAME/" &
pid=$!
spinner $pid || error_exit "File copy failed."
success "Files successfully copied."

# --------------------------------------------
# Final confirmation
# --------------------------------------------
echo "------------------------"
info "Final SSH confirmation..."
ssh -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" << 'EOF'
echo "✅ System setup files have been copied to your home directory successfully."
EOF
success "Automation setup completed."

# --------------------------------------------
# Execute remote scripts
# --------------------------------------------
echo "------------------------"
info "Running scripts on remote server..."
run_remote_command &
pid=$!
spinner $pid || error_exit "Failed to execute scripts remotely."
success "All scripts executed successfully on remote server."