#!/bin/bash

# -----------------------------------------------------------------------------
# Script: automation-scripts.sh
# Description:
#   script to deploy system setup scripts to an AWS EC2 instance.
#   - Uses Terraform outputs to fetch EC2 public IP, SSH user, and key.
#   - Copies system-setup-scripts to the remote EC2 instance.
#   - Executes updates.sh (if present) and all other shell scripts.
# -----------------------------------------------------------------------------

set -euo pipefail

# Trap to handle unexpected errors
trap 'printf "[ERROR] Script exited unexpectedly at line %s.\n" "$LINENO"' ERR

# Resolve directories
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/jenkins-server/terraform"
SCRIPTS_DIR="$ROOT_DIR/jenkins-server/system-setup-scripts"
REMOTE_DIR_NAME="system-setup-scripts"

# Check for required commands
for cmd in terraform ssh scp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf "[ERROR] Required command not found: %s\n" "$cmd"
    exit 1
  fi
done

# Verify essential directories exist
if [ ! -d "$TERRAFORM_DIR" ] || [ ! -d "$SCRIPTS_DIR" ]; then
  printf "[ERROR] Required directory not found.\n"
  printf "  Terraform: %s\n" "$TERRAFORM_DIR"
  printf "  Scripts: %s\n" "$SCRIPTS_DIR"
  exit 1
fi

# Fetch Terraform outputs
cd "$TERRAFORM_DIR"
PUBLIC_IP=$(terraform output -raw jenkins_instance_public_ip)
SSH_USER=$(terraform output -raw default_ec2_username)
PRIVATE_KEY=$(terraform output -raw private_key_file)

if [[ -z "$PUBLIC_IP" || -z "$SSH_USER" || -z "$PRIVATE_KEY" ]]; then
  printf "[ERROR] Missing required Terraform output values.\n"
  exit 1
fi

# Confirm contents and remote info
printf "\n[INFO] Ready to deploy scripts to: %s@%s\n" "$SSH_USER" "$PUBLIC_IP"
printf "[INFO] Scripts directory: %s\n" "$SCRIPTS_DIR"
printf "[INFO] Files to copy:\n"
find "$SCRIPTS_DIR" -type f | sed "s|$ROOT_DIR/|  - |"

# User confirmation
printf "\n[INPUT] Proceed with file transfer and remote execution? (yes/no): "
read -r CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  printf "[INFO] Operation cancelled by user.\n"
  exit 0
fi

# Define SSH and SCP commands
SSH_CMD="ssh -i \"$PRIVATE_KEY\" $SSH_USER@$PUBLIC_IP"
SCP_CMD="scp -i \"$PRIVATE_KEY\""

# Transfer and execute scripts remotely
printf "[INFO] Transferring files...\n"
$SSH_CMD "rm -rf ~/$REMOTE_DIR_NAME && mkdir -p ~/$REMOTE_DIR_NAME"
$SCP_CMD -r "$SCRIPTS_DIR" "$SSH_USER@$PUBLIC_IP:~/"

printf "[INFO] Executing scripts on remote host...\n"
$SSH_CMD bash <<EOF
  set -e
  cd ~/$REMOTE_DIR_NAME

  if [ -f "updates.sh" ]; then
    chmod +x updates.sh
    printf "[INFO] Running updates.sh...\n"
    ./updates.sh
  else
    printf "[WARNING] updates.sh not found. Skipping...\n"
  fi

  for script in \$(ls -1 *.sh 2>/dev/null | grep -v '^updates.sh$'); do
    chmod +x "\$script"
    printf "[INFO] Executing %s...\n" "\$script"
    "./\$script"
  done
EOF

printf "\n✅ Deployment completed successfully to %s@%s\n" "$SSH_USER" "$PUBLIC_IP"