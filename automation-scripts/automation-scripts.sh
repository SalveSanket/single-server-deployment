#!/bin/bash

# ------------------------------------------
# Production-Ready Script to Copy System Setup Scripts
# ------------------------------------------
# This script locates Terraform outputs for an AWS EC2 instance
# and securely copies the system-setup-scripts directory from
# jenkins-server/ to the remote EC2 instance.
# ------------------------------------------

set -e  # Exit on error

# Resolve project root (assuming this script lives in /automation-scripts/)
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/jenkins-server/terraform"
SCRIPTS_DIR="$ROOT_DIR/jenkins-server/system-setup-scripts"
REMOTE_DIR_NAME="system-setup-scripts"

# Check if Terraform and scripts directories exist
if [ ! -d "$TERRAFORM_DIR" ]; then
  echo "[ERROR] Terraform directory not found: $TERRAFORM_DIR"
  exit 1
fi

if [ ! -d "$SCRIPTS_DIR" ]; then
  echo "[ERROR] System setup scripts directory not found: $SCRIPTS_DIR"
  exit 1
fi

# Fetch outputs
cd "$TERRAFORM_DIR"
echo "[INFO] Fetching Terraform outputs..."
PUBLIC_IP=$(terraform output -raw jenkins_instance_public_ip)
SSH_USER=$(terraform output -raw default_ec2_username)
PRIVATE_KEY=$(terraform output -raw private_key_file)

if [[ -z "$PUBLIC_IP" || -z "$SSH_USER" || -z "$PRIVATE_KEY" ]]; then
  echo "[ERROR] One or more Terraform outputs are missing."
  exit 1
fi

# Show remote info
echo "[INFO] Connecting to: $SSH_USER@$PUBLIC_IP"
echo "[INFO] Copying from: $SCRIPTS_DIR"
echo ""
echo "[INFO] Contents to be copied:"
find "$SCRIPTS_DIR" -type f | sed "s|$ROOT_DIR/||"

# Confirm before continuing
echo ""
read -p "Do you want to proceed with copying the above files to the remote server? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "[INFO] Operation cancelled."
  exit 0
fi

# Perform secure copy
echo "[INFO] Copying directory to remote server..."
scp -i "$PRIVATE_KEY" -r "$SCRIPTS_DIR" "$SSH_USER@$PUBLIC_IP:~/"

echo ""
echo "✅ Successfully copied '$REMOTE_DIR_NAME' to $SSH_USER@$PUBLIC_IP"