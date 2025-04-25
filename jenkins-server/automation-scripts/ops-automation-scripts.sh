#!/bin/bash

# -----------------------------------------------------------------------------
# Script: ops-automation-scripts.sh
# Description:
#   Interactively manage the remote 'system-setup-scripts' directory on a Jenkins EC2 server.
#   Uses Terraform to retrieve instance connection info.
# -----------------------------------------------------------------------------

set -euo pipefail
trap 'printf "[ERROR] Script failed unexpectedly at line %s.\n" "$LINENO"' ERR

# Define paths
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/jenkins-server/terraform"
LOCAL_SCRIPTS_DIR="$ROOT_DIR/jenkins-server/system-setup-scripts"
REMOTE_DIR="system-setup-scripts"

# Validate Terraform directory
if [ ! -d "$TERRAFORM_DIR" ]; then
  printf "[ERROR] Terraform directory not found: %s\n" "$TERRAFORM_DIR"
  exit 1
fi

# Get Terraform outputs
cd "$TERRAFORM_DIR"
printf "[INFO] Fetching Terraform outputs...\n"
PUBLIC_IP=$(terraform output -raw jenkins_instance_public_ip)
SSH_USER=$(terraform output -raw default_ec2_username)
PRIVATE_KEY=$(terraform output -raw private_key_file)

if [[ -z "$PUBLIC_IP" || -z "$SSH_USER" || -z "$PRIVATE_KEY" ]]; then
  printf "[ERROR] One or more Terraform outputs are missing.\n"
  exit 1
fi

SSH_CMD="ssh -i \"$PRIVATE_KEY\" -o StrictHostKeyChecking=no $SSH_USER@$PUBLIC_IP"
SCP_CMD="scp -i \"$PRIVATE_KEY\""

printf "[INFO] Connected to %s@%s\n" "$SSH_USER" "$PUBLIC_IP"

while true; do
  REMOTE_EXISTS=$(eval "$SSH_CMD '[ -d ~/$REMOTE_DIR ] && echo yes || echo no'")

  if [[ "$REMOTE_EXISTS" == "yes" ]]; then
    printf "\n[INFO] '%s' exists on remote server. Contents:\n" "$REMOTE_DIR"
    eval "$SSH_CMD 'ls -lh ~/$REMOTE_DIR'"

    printf "\nChoose an operation:\n"
    printf "1. Download all files from remote to local\n"
    printf "2. Upload all files from local to remote (overwrite)\n"
    printf "3. Delete remote '%s' directory\n" "$REMOTE_DIR"
    printf "4. Upload a specific file to remote\n"
    printf "5. Download a specific file from remote\n"
    printf "6. Cancel\n"

    read -rp "Enter your choice (1-6): " CHOICE

    case $CHOICE in
      1)
        printf "[INFO] Downloading remote directory to local...\n"
        eval "$SCP_CMD -r $SSH_USER@$PUBLIC_IP:~/$REMOTE_DIR \"$LOCAL_SCRIPTS_DIR\""
        ;;
      2)
        printf "[INFO] Uploading local directory to remote...\n"
        eval "$SCP_CMD -r \"$LOCAL_SCRIPTS_DIR\" $SSH_USER@$PUBLIC_IP:~/"
        ;;
      3)
        printf "[INFO] Deleting remote directory...\n"
        eval "$SSH_CMD 'rm -rf ~/$REMOTE_DIR'"
        ;;
      4)
        printf "[INFO] Local files:\n"
        find "$LOCAL_SCRIPTS_DIR" -type f | sed "s|$ROOT_DIR/|  - |"
        read -rp "Enter relative path to file: " FILE
        FULL_PATH="$LOCAL_SCRIPTS_DIR/$FILE"
        if [[ -f "$FULL_PATH" ]]; then
          eval "$SCP_CMD \"$FULL_PATH\" $SSH_USER@$PUBLIC_IP:~/$REMOTE_DIR/"
          printf "[INFO] File uploaded.\n"
          # Ensure file is executable on remote
          eval "$SSH_CMD 'chmod +x ~/$REMOTE_DIR/$FILE'"
          # Ask user if they want to execute the uploaded script
          read -rp "Do you want to execute this script? (yes/no): " EXECUTE
          if [[ "$EXECUTE" == "yes" ]]; then
            eval "$SSH_CMD 'bash ~/$REMOTE_DIR/$FILE'"
            printf "[INFO] Script executed successfully.\n"
          fi
        else
          printf "[ERROR] File not found: %s\n" "$FULL_PATH"
        fi
        ;;
      5)
        printf "[INFO] Remote files:\n"
        eval "$SSH_CMD 'ls -lh ~/$REMOTE_DIR'"
        read -rp "Enter filename to download: " FILE
        eval "$SCP_CMD $SSH_USER@$PUBLIC_IP:~/$REMOTE_DIR/$FILE \"$LOCAL_SCRIPTS_DIR/\""
        printf "[INFO] File downloaded to local directory.\n"
        ;;
      *)
        printf "[INFO] Operation cancelled.\n"
        ;;
    esac
  else
    printf "[INFO] '%s' does not exist on the remote server.\n" "$REMOTE_DIR"
    read -rp "Would you like to upload local '$REMOTE_DIR' to remote server now? (yes/no): " CONFIRM
    if [[ "$CONFIRM" == "yes" ]]; then
      eval "$SCP_CMD -r \"$LOCAL_SCRIPTS_DIR\" $SSH_USER@$PUBLIC_IP:~/"
      printf "[INFO] Uploaded local '%s' to remote server.\n" "$REMOTE_DIR"
    else
      printf "[INFO] No action taken.\n"
    fi
  fi

  printf "\n✅ Operation complete.\n"
  read -rp "Would you like to perform another operation? (yes/no): " AGAIN

  while [[ "$AGAIN" != "yes" && "$AGAIN" != "no" ]]; do
    read -rp "Please enter 'yes' to continue or 'no' to exit: " AGAIN
  done

  if [[ "$AGAIN" == "no" ]]; then
    printf "[INFO] Exiting script.\n"
    break
  fi
done