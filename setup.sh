#!/bin/bash

# Color codes
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m' # No Color

# Functions for printing messages
print_header() {
  echo -e "${YELLOW}"
  echo "======================================"
  echo "  $1"
  echo "======================================"
  echo -e "${NC}"
}

print_info() {
  echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Spinner function
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while kill -0 $pid 2>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "      \b\b\b\b\b\b"
}

run_script_with_spinner() {
  local script_path=$1
  print_info "Running script: $script_path"
  bash "$script_path" &
  local pid=$!
  spinner $pid
  wait $pid
  local status=$?
  if [ $status -eq 0 ]; then
    print_success "Script completed successfully: $script_path"
  else
    print_error "Script failed with status $status: $script_path"
    exit $status
  fi
}

ROOT_DIR=$(pwd)

print_header "Starting Automation Scripts Execution"

# Jenkins server automation scripts
JENKINS_DIR="jenkins-server/automation-scripts"
JENKINS_SCRIPT="automation-scripts.sh"

if [ -d "$JENKINS_DIR" ]; then
  print_info "Found Jenkins automation directory: $JENKINS_DIR"
  cd "$JENKINS_DIR" || { print_error "Failed to enter directory $JENKINS_DIR"; exit 1; }
  if [ -x "$JENKINS_SCRIPT" ]; then
    run_script_with_spinner "./$JENKINS_SCRIPT"
  else
    print_error "Script $JENKINS_SCRIPT not found or not executable in $JENKINS_DIR"
    exit 1
  fi
  cd "$ROOT_DIR" || { print_error "Failed to return to root directory $ROOT_DIR"; exit 1; }
else
  print_error "Directory not found: $JENKINS_DIR"
  exit 1
fi

# Prod server automation scripts
PROD_DIR="prod-server/automation-scripts"
PROD_SCRIPT="automation-scripts.sh"

if [ -d "$PROD_DIR" ]; then
  print_info "Found Prod automation directory: $PROD_DIR"
  cd "$PROD_DIR" || { print_error "Failed to enter directory $PROD_DIR"; exit 1; }
  if [ -x "$PROD_SCRIPT" ]; then
    run_script_with_spinner "./$PROD_SCRIPT"
  else
    print_error "Script $PROD_SCRIPT not found or not executable in $PROD_DIR"
    exit 1
  fi
  cd "$ROOT_DIR" || { print_error "Failed to return to root directory $ROOT_DIR"; exit 1; }
else
  print_error "Directory not found: $PROD_DIR"
  exit 1
fi

print_header "All Automation Scripts Executed Successfully"
