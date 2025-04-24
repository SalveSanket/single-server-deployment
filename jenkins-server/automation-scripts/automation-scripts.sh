#!/bin/bash

# ------------------------------------------
# Production-Ready Script to Copy Automation Scripts
# ------------------------------------------
# This script locates Terraform outputs for an AWS EC2 instance
# and securely copies the system-setup-scripts directory to it.
# ------------------------------------------

set -e  # Exit on error

# Define paths
ROOT_DIR="$(dirname $(dirname $(dirname "$0")))"
TERRAFORM_DIR="$ROOT_DIR/jenkins-server/terraform"
SCRIPTS_DIR="$ROOT_DIR/system-setup-scripts"

# Ensure Terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
  echo "[ERROR] Terraform directory not found: $TERRAFORM_DIR"
  exit 1
fi

# Change to Terraform directory and get outputs
cd "$TERRAFORM_DIR"
echo "[INFO] Extracting Terraform outputs..."
PUBLIC_IP=$(terraform output -raw jenkins_instance_public_ip)
SSH_USER=$(terraform output -raw default_ec2_username)
PRIVATE_KEY=$(terraform output -raw private_key_file)

# Validate outputs
if [[ -z "$PUBLIC_IP" || -z "$SSH_USER" || -z "$PRIVATE_KEY" ]]; then
  echo "[ERROR] Missing Terraform output values. Ensure Terraform is applied and outputs are defined."
  exit 1
fi

# Confirm destination
echo "[INFO] Connecting to: $SSH_USER@$PUBLIC_IP"
echo "[INFO] Using private key: $PRIVATE_KEY"
echo "[INFO] Automation scripts directory: $SCRIPTS_DIR"

# Show directories and files to be copied
echo "\n[INFO] The following files will be copied to the server:"
find "$SCRIPTS_DIR" -type f | sed "s|$ROOT_DIR/||"

echo -n "\nDo you want to proceed with copying these files? (yes/no): "
read CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "[INFO] Aborting file copy."
  exit 0
fi

# Perform secure copy
echo "\n[INFO] Copying automation scripts to the server..."
sftp -i "$PRIVATE_KEY" -oStrictHostKeyChecking=no -r "$SCRIPTS_DIR" "$SSH_USER@$PUBLIC_IP":~/

echo "\n✅ Automation scripts successfully copied to $SSH_USER@$PUBLIC_IP"