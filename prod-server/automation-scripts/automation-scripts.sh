#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# --------------------------------------------
# Function to display error messages and exit
# --------------------------------------------
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

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
        echo "Operation cancelled by the user."
        exit 0
    fi
}

# --------------------------------------------
# Resolve project root directory dynamically
# --------------------------------------------
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# --------------------------------------------
# Define paths
# --------------------------------------------
TERRAFORM_DIR="$ROOT_DIR/prod-server/terraform"
SYSTEM_SETUP_DIR="$ROOT_DIR/prod-server/system-setup-scripts"
REMOTE_DIR_NAME="system-setup-scripts"
PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH:-$HOME/.ssh/ProdKey}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-$HOME/.ssh/ProdKey.pub}"

# --------------------------------------------
# Check prerequisites
# --------------------------------------------
for path in "$TERRAFORM_DIR" "$SYSTEM_SETUP_DIR" "$PRIVATE_KEY_PATH" "$PUBLIC_KEY_PATH"; do
    check_exists "$path" "$(basename "$path")"
done

# Check required commands exist
for cmd in terraform scp ssh; do
    command -v "$cmd" >/dev/null 2>&1 || error_exit "$cmd command not found. Please install it."
done

# --------------------------------------------
# Fetch Terraform output values
# --------------------------------------------
PROD_SERVER_IP=$(terraform -chdir="$TERRAFORM_DIR" output -raw prodserver_public_ip)
PROD_SERVER_URL=$(terraform -chdir="$TERRAFORM_DIR" output -raw prodserver_url)
DEFAULT_SSH_USER=$(terraform -chdir="$TERRAFORM_DIR" output -raw default_ssh_user)

# Validate outputs
[ -z "$PROD_SERVER_IP" ] && error_exit "prodserver_public_ip output is missing!"
[ -z "$DEFAULT_SSH_USER" ] && error_exit "default_ssh_user output is missing!"

# --------------------------------------------
# Show what will be copied
# --------------------------------------------
echo "The following files from '$SYSTEM_SETUP_DIR' will be copied to the remote server under the home directory (~/$REMOTE_DIR_NAME):"
echo ""
for file in "$SYSTEM_SETUP_DIR"/*; do
    echo "  - $(basename "$file")"
done
echo ""

ask_confirmation "Proceed with copying files?"

# --------------------------------------------
# Prepare remote target directory
# --------------------------------------------
echo "Ensuring remote directory ~/$REMOTE_DIR_NAME exists..."
ssh -i "$PRIVATE_KEY_PATH" -o StrictHostKeyChecking=accept-new "$DEFAULT_SSH_USER@$PROD_SERVER_IP" "mkdir -p ~/$REMOTE_DIR_NAME" || error_exit "Failed to create directory on remote server."

# --------------------------------------------
# Copy files
# --------------------------------------------
echo "Copying files to ~$REMOTE_DIR_NAME on remote server..."
scp -i "$PRIVATE_KEY_PATH" -o StrictHostKeyChecking=accept-new -r "$SYSTEM_SETUP_DIR/"* "$DEFAULT_SSH_USER@$PROD_SERVER_IP:~/$REMOTE_DIR_NAME/" || error_exit "File copy failed."

echo "Files successfully copied to $DEFAULT_SSH_USER@$PROD_SERVER_IP:~/$REMOTE_DIR_NAME"

# --------------------------------------------
# Final SSH confirmation
# --------------------------------------------
ssh -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" << 'EOF'
    echo "✅ System setup files have been copied to your home directory successfully."
EOF

echo "Automation completed successfully. 🚀"