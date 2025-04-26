#!/bin/bash

set -euo pipefail

# --------------------------------------------
# Colors and Styles
# --------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --------------------------------------------
# Functions
# --------------------------------------------

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    tput civis  # hide cursor
    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#spinstr}; i++ )); do
            printf "\r${YELLOW}[%c]${NC} " "${spinstr:i:1}"
            sleep $delay
        done
    done
    printf "\r"
    tput cnorm  # show cursor
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error_exit() {
    echo -e "${RED}❌ ERROR: $1${NC}"
    exit 1
}

section() {
    echo ""
    echo -e "${YELLOW}========================================"
    echo "     $1"
    echo -e "========================================${NC}"
    echo ""
}

ask_confirmation() {
    read -rp "$1 (yes/no): " response
    if [[ "$response" != "yes" ]]; then
        warn "Operation cancelled by the user."
        exit 0
    fi
}

retry_command() {
    local retries=3
    local count=0
    until "$@"; do
        exit_code=$?
        wait_time=$((2 ** count))
        if [ $count -lt $retries ]; then
            warn "Command failed with exit code $exit_code. Retrying in $wait_time seconds..."
            sleep $wait_time
            ((count++))
        else
            error_exit "Command failed after $retries attempts."
        fi
    done
}

# --------------------------------------------
# Variables
# --------------------------------------------

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/prod-server/terraform"
SYSTEM_SETUP_DIR="$ROOT_DIR/prod-server/system-setup-scripts"
REMOTE_DIR_NAME="system-setup-scripts"
PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH:-$HOME/.ssh/ProdKey}"

# --------------------------------------------
# Fetch Terraform Output Values
# --------------------------------------------

section "Fetching Terraform Outputs"

PROD_SERVER_IP=$(terraform -chdir="$TERRAFORM_DIR" output -raw prodserver_public_ip)
DEFAULT_SSH_USER=$(terraform -chdir="$TERRAFORM_DIR" output -raw default_ssh_user)

if [ -z "$PROD_SERVER_IP" ] || [ -z "$DEFAULT_SSH_USER" ]; then
    error_exit "Terraform output did not provide necessary values!"
fi

success "Terraform values fetched."
info "Server IP  : $PROD_SERVER_IP"
info "SSH User   : $DEFAULT_SSH_USER"

# --------------------------------------------
# SSH and Check Remote Directory
# --------------------------------------------

section "Connecting to Remote Server"

info "Connecting to remote server..."
info "Checking if remote directory exists..."

REMOTE_CHECK=$(ssh -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" "[ -d \"/home/$DEFAULT_SSH_USER/$REMOTE_DIR_NAME\" ] && echo 'exists' || echo 'not_exists'")

show_menu_and_handle_operations() {
    while true; do
        echo "------------------------"
        echo ""
        echo -e "${YELLOW}Remote directory contents:${NC}"
        ssh -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" "ls -lh /home/$DEFAULT_SSH_USER/$REMOTE_DIR_NAME" &
        pid=$!
        spinner $pid
        wait $pid
        echo ""
        echo "------------------------"
        echo -e "${BLUE}Please choose an option:${NC}"
        echo "1. Copy a new file into $REMOTE_DIR_NAME"
        echo "2. Delete a file from $REMOTE_DIR_NAME"
        echo "3. Update (overwrite) a file in $REMOTE_DIR_NAME"
        echo "4. Delete the entire $REMOTE_DIR_NAME directory"
        echo "5. Exit"
        read -rp "Enter your choice [1-5]: " choice

        case "$choice" in
            1)
                read -rp "Enter the path to the local file to copy: " local_file
                if [[ ! -f "$local_file" ]]; then
                    warn "File does not exist: $local_file"
                else
                    remote_path="/home/$DEFAULT_SSH_USER/$REMOTE_DIR_NAME/$(basename "$local_file")"
                    info "Copying $local_file to $remote_path"
                    scp -i "$PRIVATE_KEY_PATH" "$local_file" "$DEFAULT_SSH_USER@$PROD_SERVER_IP:$remote_path" &
                    pid=$!
                    spinner $pid
                    wait $pid && success "File copied successfully." || warn "Failed to copy file."
                fi
                ;;
            2)
                read -rp "Enter the filename to delete from $REMOTE_DIR_NAME: " del_file
                ask_confirmation "Are you sure you want to delete $del_file from $REMOTE_DIR_NAME?"
                ssh -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" "rm -f /home/$DEFAULT_SSH_USER/$REMOTE_DIR_NAME/$del_file" &
                pid=$!
                spinner $pid
                wait $pid && success "File deleted." || warn "Failed to delete file."
                ;;
            3)
                echo ""
                echo "Available files in system-setup-scripts:"
                file_list=()
                while IFS= read -r filepath; do
                    filename=$(basename "$filepath")
                    file_list+=("$filename")
                    echo " - $filename"
                done < <(find "$SYSTEM_SETUP_DIR" -maxdepth 1 -type f)

                if [ ${#file_list[@]} -eq 0 ]; then
                    warn "No files available to update."
                    break
                fi

                read -rp "Enter the filename from system-setup-scripts to update (overwrite): " selected_file

                if [[ ! " ${file_list[*]} " =~ " ${selected_file} " ]]; then
                    warn "File does not exist in system-setup-scripts: $selected_file"
                else
                    local_file="$SYSTEM_SETUP_DIR/$selected_file"
                    remote_path="/home/$DEFAULT_SSH_USER/$REMOTE_DIR_NAME/$selected_file"
                    ask_confirmation "Are you sure you want to overwrite $remote_path?"
                    scp -i "$PRIVATE_KEY_PATH" "$local_file" "$DEFAULT_SSH_USER@$PROD_SERVER_IP:$remote_path" &
                    pid=$!
                    spinner $pid
                    wait $pid && success "File updated successfully." || warn "Failed to update file."
                fi
                ;;
            4)
                ask_confirmation "Are you sure you want to delete the entire $REMOTE_DIR_NAME directory?"
                ssh -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" "rm -rf /home/$DEFAULT_SSH_USER/$REMOTE_DIR_NAME" &
                pid=$!
                spinner $pid
                wait $pid && success "Directory deleted." || warn "Failed to delete directory."
                break
                ;;
            5)
                info "Exiting menu."
                break
                ;;
            *)
                warn "Invalid choice. Please select a valid option."
                ;;
        esac

        # After each operation (except exit and delete directory), ask if user wants to perform another operation
        if [[ "$choice" != "4" && "$choice" != "5" ]]; then
            echo "------------------------"
            echo ""
            echo -e "${YELLOW}Remote directory contents:${NC}"
            ssh -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" "ls -lh /home/$DEFAULT_SSH_USER/$REMOTE_DIR_NAME" &
            pid=$!
            spinner $pid
            wait $pid
            echo ""
            read -rp "Do you want to perform another operation? (yes/no): " continue_response
            if [[ "$continue_response" != "yes" ]]; then
                info "Exiting menu."
                break
            fi
        fi
    done
}

if [[ "$REMOTE_CHECK" == "exists" ]]; then
    success "Remote directory '$REMOTE_DIR_NAME' found!"
    show_menu_and_handle_operations
else
    warn "Remote directory '$REMOTE_DIR_NAME' not found."
    ask_confirmation "Would you like to copy it now?"

    # --------------------------------------------
    # Copy Directory to Remote
    # --------------------------------------------
    section "Copying system-setup-scripts to Remote"

    DIR_SIZE_KB=$(du -sk "$SYSTEM_SETUP_DIR" | awk '{print $1}')
    DIR_SIZE_BYTES=$((DIR_SIZE_KB * 1024))

    info "Directory size: ${DIR_SIZE_KB} KB"

    retry_command bash -c "
        tar -czf - -C '$(dirname "$SYSTEM_SETUP_DIR")' '$(basename "$SYSTEM_SETUP_DIR")' | \
        pv -s $DIR_SIZE_BYTES | \
        ssh -i '$PRIVATE_KEY_PATH' '$DEFAULT_SSH_USER@$PROD_SERVER_IP' 'tar -xzf - -C /home/$DEFAULT_SSH_USER'
    "

    success "Successfully copied 'system-setup-scripts' to /home/$DEFAULT_SSH_USER/"

    # --------------------------------------------
    # List Copied Files on Remote Server
    # --------------------------------------------
    section "Copied Files on Remote Server"
    info "Listing copied files and directories:"
    ssh -i "$PRIVATE_KEY_PATH" "$DEFAULT_SSH_USER@$PROD_SERVER_IP" "ls -lh /home/$DEFAULT_SSH_USER/system-setup-scripts" &
    pid=$!
    spinner $pid
    wait $pid
fi

# --------------------------------------------
# Final Message
# --------------------------------------------

section "Automation Completed Successfully"
success "You are ready to proceed!"