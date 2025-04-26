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
# Spinner function for background tasks
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
# Function to check if a file or directory exists
# --------------------------------------------
check_exists() {
    if [ ! -e "$1" ]; then
        error_exit "$2 not found at $1!"
    fi
}

# --------------------------------------------
# Function to ask user for confirmation
# --------------------------------------------
ask_confirmation() {
    read -r -p "$1 (yes/no): " response
    if [[ "$response" != "yes" ]]; then
        info "Operation cancelled by the user."
        exit 0
    fi
}

# --------------------------------------------
# Resolve project root directory dynamically
# --------------------------------------------
echo "------------------------"
info "Resolving project root directory..."
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
success "Project root directory resolved to $ROOT_DIR"

# --------------------------------------------
# Define paths
# --------------------------------------------
echo "------------------------"
info "Defining paths..."
TERRAFORM_DIR="$ROOT_DIR/prod-server/terraform"
SYSTEM_SETUP_DIR="$ROOT_DIR/prod-server/system-setup-scripts"
REMOTE_DIR_NAME="system-setup-scripts"
PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH:-$HOME/.ssh/ProdKey}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-$HOME/.ssh/ProdKey.pub}"
success "Paths defined."

# --------------------------------------------
# Check prerequisites
# --------------------------------------------
echo "------------------------"
info "Checking prerequisites..."
for path in "$TERRAFORM_DIR" "$SYSTEM_SETUP_DIR" "$PRIVATE_KEY_PATH" "$PUBLIC_KEY_PATH"; do
    check_exists "$path" "$(basename "$path")"
done

for cmd in terraform scp ssh; do
    command -v "$cmd" >/dev/null 2>&1 || error_exit "$cmd command not found. Please install it."
done
success "All prerequisites are met."

# --------------------------------------------
# Fetch Terraform output values
# --------------------------------------------
echo "------------------------"
info "Fetching Terraform output values..."
PROD_SERVER_IP=$(terraform -chdir="$TERRAFORM_DIR" output -raw prodserver_public_ip)
PROD_SERVER_URL=$(terraform -chdir="$TERRAFORM_DIR" output -raw prodserver_url)
DEFAULT_SSH_USER=$(terraform -chdir="$TERRAFORM_DIR" output -raw default_ssh_user)

[ -z "$PROD_SERVER_IP" ] && error_exit "prodserver_public_ip output is missing!"
[ -z "$DEFAULT_SSH_USER" ] && error_exit "default_ssh_user output is missing!"
success "Terraform output values fetched."

# --------------------------------------------
# Show what will be copied
# --------------------------------------------
echo "------------------------"
info "The following files from '$SYSTEM_SETUP_DIR' will be copied to the remote server under the home directory (~/$REMOTE_DIR_NAME):"
echo ""
for file in "$SYSTEM_SETUP_DIR"/*; do
    echo "  - $(basename "$file")"
done
echo ""

ask_confirmation "Proceed with copying files?"

# --------------------------------------------
# Prepare remote target directory
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
success "Files successfully copied to $DEFAULT_SSH_USER@$PROD_SERVER_IP:~/$REMOTE_DIR_NAME"

# --------------------------------------------
# Final SSH confirmation
# --------------------------------------------
echo "------------------------"
info "Final SSH confirmation..."
ssh -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" << 'EOF' &
    echo "✅ System setup files have been copied to your home directory successfully."
EOF
pid=$!
spinner $pid

success "Automation completed successfully. 🚀"