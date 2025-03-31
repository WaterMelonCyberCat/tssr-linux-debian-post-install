#!/bin/bash

# === VARIABLES ===
# TIMESTAMP: Current date and time in the format YYYYMMDD_HHMMSS, used for log file naming
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# LOG_DIR: Directory where log files will be stored
LOG_DIR="./logs"

# LOG_FILE: Specific log file for this installation, includes a timestamp
LOG_FILE="$LOG_DIR/postinstall_$TIMESTAMP.log"

# CONFIG_DIR: Directory where configuration files are stored
CONFIG_DIR="./config"

# PACKAGE_LIST: Path to the file containing the list of packages to install
PACKAGE_LIST="./lists/packages.txt"

# USERNAME: Name of the currently logged-in user
USERNAME=$(logname)

# USER_HOME: Home directory of the logged-in user
USER_HOME="/home/$USERNAME"

# === FUNCTIONS ===

# log(): Logs messages with a timestamp to both the console and the log file
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# check_and_install(): Checks if a package is installed, and installs it if not
check_and_install() {
  local pkg=$1
  if dpkg -s "$pkg" &>/dev/null; then
    log "$pkg is already installed."
  else
    log "Installing $pkg..."
    apt install -y "$pkg" &>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
      log "$pkg successfully installed."
    else
      log "Failed to install $pkg."
    fi
  fi
}

# ask_yes_no(): Prompts the user with a yes/no question and returns 0 for yes, 1 for no
ask_yes_no() {
  read -p "$1 [y/N]: " answer
  case "$answer" in
    [Yy]* ) return 0 ;;  # User answered yes
    * ) return 1 ;;      # Default to no
  esac
}

# === INITIAL SETUP ===

# Create the log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Create the log file
touch "$LOG_FILE"

# Log the start of the script and the logged-in user
log "Starting post-installation script. Logged user: $USERNAME"

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  log "This script must be run as root."
  exit 1
fi

# === 1. SYSTEM UPDATE ===

# Update and upgrade system packages
log "Updating system packages..."
apt update && apt upgrade -y &>>"$LOG_FILE"

# === 2. PACKAGE INSTALLATION ===

# Check if the package list file exists
if [ -f "$PACKAGE_LIST" ]; then
  log "Reading package list from $PACKAGE_LIST"
  # Read each package from the file and install it
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    # Skip empty lines and comments
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
    check_and_install "$pkg"
  done < "$PACKAGE_LIST"
else
  log "Package list file $PACKAGE_LIST not found. Skipping package installation."
fi

# === 3. UPDATE MOTD ===

# Update the Message of the Day (MOTD) if the file exists
if [ -f "$CONFIG_DIR/motd.txt" ]; then
  cp "$CONFIG_DIR/motd.txt" /etc/motd
  log "MOTD updated."
else
  log "motd.txt not found."
fi

# === 4. CUSTOM .bashrc ===

# Append custom content to the user's .bashrc if the file exists
if [ -f "$CONFIG_DIR/bashrc.append" ]; then
  cat "$CONFIG_DIR/bashrc.append" >> "$USER_HOME/.bashrc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
  log ".bashrc customized."
else
  log "bashrc.append not found."
fi

# === 5. CUSTOM .nanorc ===

# Append custom content to the user's .nanorc if the file exists
if [ -f "$CONFIG_DIR/nanorc.append" ]; then
  cat "$CONFIG_DIR/nanorc.append" >> "$USER_HOME/.nanorc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.nanorc"
  log ".nanorc customized."
else
  log "nanorc.append not found."
fi

# === 6. ADD SSH PUBLIC KEY ===

# Prompt the user to add an SSH public key
if ask_yes_no "Would you like to add a public SSH key?"; then
  read -p "Paste your public SSH key: " ssh_key
  mkdir -p "$USER_HOME/.ssh"
  echo "$ssh_key" >> "$USER_HOME/.ssh/authorized_keys"
  chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
  chmod 700 "$USER_HOME/.ssh"
  chmod 600 "$USER_HOME/.ssh/authorized_keys"
  log "SSH public key added."
fi

# === 7. SSH CONFIGURATION: KEY AUTH ONLY ===

# Configure SSH to allow only key-based authentication
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh
  log "SSH configured to accept key-based authentication only."
else
  log "sshd_config file not found."
fi

# Log the completion of the script
log "Post-installation script completed."

# Exit the script
exit 0