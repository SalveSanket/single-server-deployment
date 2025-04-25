#!/bin/bash

# Function to display error messages and exit the script
function error_exit {
    echo "ERROR: $1"
    exit 1
}

# Function to check if a file or directory exists
function check_exists {
    if [ ! -e "$1" ]; then
        error_exit "$2 not found at $1!"
    fi
}

# Function to ask user for confirmation to proceed
function ask_confirmation {
    read -p "$1 (yes/no): " response
    if [[ "$response" != "yes" ]]; then
        echo "Operation cancelled by the user."
        exit 0
    fi
}

# Resolve project root directory dynamically
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Define paths for important directories and files
TERRAFORM_DIR="$ROOT_DIR/prod-server/terraform"
SYSTEM_SETUP_DIR="$ROOT_DIR/prod-server/system-setup-scripts"
REMOTE_DIR_NAME="system-setup-scripts"
PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH:-$HOME/.ssh/ProdKey}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-$HOME/.ssh/ProdKey.pub}"

# --------------------------------------------------------------
# Check if the required directories and files exist
# --------------------------------------------------------------
check_exists "$TERRAFORM_DIR" "Terraform directory"
check_exists "$SYSTEM_SETUP_DIR" "System setup scripts directory"
check_exists "$PRIVATE_KEY_PATH" "Private key"
check_exists "$PUBLIC_KEY_PATH" "Public key"

# --------------------------------------------------------------
# Fetch Terraform output values (from output.tf)
# --------------------------------------------------------------
PROD_SERVER_IP=$(terraform -chdir="$TERRAFORM_DIR" output -raw prodserver_public_ip)
PROD_SERVER_URL=$(terraform -chdir="$TERRAFORM_DIR" output -raw prodserver_url)
DEFAULT_SSH_USER=$(terraform -chdir="$TERRAFORM_DIR" output -raw default_ssh_user)

# Ensure Terraform outputs are valid
if [ -z "$PROD_SERVER_IP" ] || [ -z "$DEFAULT_SSH_USER" ]; then
    error_exit "Terraform output did not provide necessary values!"
fi

# --------------------------------------------------------------
# Show the files that will be copied and ask for user confirmation
# --------------------------------------------------------------
echo "The following files from '$SYSTEM_SETUP_DIR' will be copied to the remote server at '/tmp':"
echo ""
for file in "$SYSTEM_SETUP_DIR"/*; do
    echo "  - $file"
done
echo ""

# Ask for user confirmation before proceeding
ask_confirmation "Do you want to copy these files to the remote server?"

# --------------------------------------------------------------
# Perform the file copy operation
# --------------------------------------------------------------
echo "Copying files to $DEFAULT_SSH_USER@$PROD_SERVER_IP:/tmp"
scp -i "$PRIVATE_KEY_PATH" -r "$SYSTEM_SETUP_DIR" "$DEFAULT_SSH_USER@$PROD_SERVER_IP:/tmp" || error_exit "Failed to copy system-setup-scripts to the server."

echo "Successfully copied system-setup-scripts to $PROD_SERVER_IP:/tmp"

# --------------------------------------------------------------
# SSH into the remote server and display a confirmation message
# --------------------------------------------------------------
ssh -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" << 'EOF'
    echo "System setup directory has been copied. No setup.sh script to run."
EOF

# Check if SSH execution was successful
if [ $? -ne 0 ]; then
    error_exit "SSH execution failed."
fi

# --------------------------------------------------------------
# Final success message
# --------------------------------------------------------------
echo "Automation completed successfully."