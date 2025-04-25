#!/bin/bash

# ------------------------------------------
# Production-Ready Script: Ops Automation Scripts Manager
# ------------------------------------------
# This script fetches necessary Terraform outputs to connect to
# a Jenkins EC2 server and provides a menu to manage the remote
# 'system-setup-scripts' directory interactively.
# ------------------------------------------

set -e

# Define paths
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/jenkins-server/terraform"
LOCAL_SCRIPTS_DIR="$ROOT_DIR/jenkins-server/system-setup-scripts"
REMOTE_DIR="system-setup-scripts"

# Validate Terraform directory
if [ ! -d "$TERRAFORM_DIR" ]; then
  echo "[ERROR] Terraform directory not found: $TERRAFORM_DIR"
  exit 1
fi

# Get Terraform outputs
cd "$TERRAFORM_DIR"
echo "[INFO] Fetching Terraform outputs..."
PUBLIC_IP=$(terraform output -raw jenkins_instance_public_ip)
SSH_USER=$(terraform output -raw default_ec2_username)
PRIVATE_KEY=$(terraform output -raw private_key_file)

if [[ -z "$PUBLIC_IP" || -z "$SSH_USER" || -z "$PRIVATE_KEY" ]]; then
  echo "[ERROR] One or more Terraform outputs are missing."
  exit 1
fi

echo "[INFO] Connecting to $SSH_USER@$PUBLIC_IP with key $PRIVATE_KEY"

while true; do
  REMOTE_EXISTS=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$PUBLIC_IP" "[ -d ~/$REMOTE_DIR ] && echo yes || echo no")

  if [[ "$REMOTE_EXISTS" == "yes" ]]; then
    echo -e "\n[INFO] '$REMOTE_DIR' exists on remote server. Contents:"
    ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$PUBLIC_IP" "ls -lh ~/$REMOTE_DIR"

    echo -e "\nChoose an operation:
1. Download all files from remote to local
2. Upload all files from local to remote (overwrite)
3. Delete remote 'system-setup-scripts' directory
4. Upload a specific file to remote
5. Download a specific file from remote
6. Cancel"

    read -p "Enter your choice (1-6): " CHOICE

    case $CHOICE in
      1)
        echo "[INFO] Downloading remote directory to local..."
        scp -i "$PRIVATE_KEY" -r "$SSH_USER@$PUBLIC_IP:~/$REMOTE_DIR" "$LOCAL_SCRIPTS_DIR"
        ;;
      2)
        echo "[INFO] Uploading local directory to remote..."
        scp -i "$PRIVATE_KEY" -r "$LOCAL_SCRIPTS_DIR" "$SSH_USER@$PUBLIC_IP:~/"
        ;;
      3)
        echo "[INFO] Deleting remote directory..."
        ssh -i "$PRIVATE_KEY" "$SSH_USER@$PUBLIC_IP" "rm -rf ~/$REMOTE_DIR"
        echo "[INFO] Deleted."
        ;;
      4)
        echo "[INFO] Local files:"
        find "$LOCAL_SCRIPTS_DIR" -type f | sed "s|$ROOT_DIR/||"
        read -p "Enter relative path to file: " FILE
        if [[ -f "$LOCAL_SCRIPTS_DIR/$FILE" ]]; then
          scp -i "$PRIVATE_KEY" "$LOCAL_SCRIPTS_DIR/$FILE" "$SSH_USER@$PUBLIC_IP:~/$REMOTE_DIR/"
          echo "[INFO] File uploaded."
        else
          echo "[ERROR] File not found."
        fi
        ;;
      5)
        echo "[INFO] Downloading file from remote."
        ssh -i "$PRIVATE_KEY" "$SSH_USER@$PUBLIC_IP" "ls -lh ~/$REMOTE_DIR"
        read -p "Enter filename to download: " FILE
        scp -i "$PRIVATE_KEY" "$SSH_USER@$PUBLIC_IP:~/$REMOTE_DIR/$FILE" "$LOCAL_SCRIPTS_DIR/"
        echo "[INFO] File downloaded to local directory."
        ;;
      *)
        echo "[INFO] Operation cancelled."
        ;;
    esac
  else
    echo "[INFO] '$REMOTE_DIR' does not exist on the remote server."
    read -p "Would you like to upload local '$REMOTE_DIR' to remote server now? (yes/no): " CONFIRM
    if [[ "$CONFIRM" == "yes" ]]; then
      scp -i "$PRIVATE_KEY" -r "$LOCAL_SCRIPTS_DIR" "$SSH_USER@$PUBLIC_IP:~/"
      echo "[INFO] Uploaded local '$REMOTE_DIR' to remote server."
    else
      echo "[INFO] No action taken."
    fi
  fi

  echo -e "✅ Operation complete."
  echo ""
  read -p "Would you like to perform another operation? (yes/no): " AGAIN

  while [[ "$AGAIN" != "yes" && "$AGAIN" != "no" ]]; do
    read -p "Please enter 'yes' to continue or 'no' to exit: " AGAIN
  done

  if [[ "$AGAIN" == "no" ]]; then
    echo "[INFO] Exiting script."
    break
  fi

done