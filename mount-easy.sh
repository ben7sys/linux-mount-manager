#!/bin/bash

# Mount Management Script
# Version: 1.0
# This script manages systemd mount units.

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directory paths
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
MOUNT_FILES_DIR="$SCRIPT_DIR"
SYSTEMD_DIR="/etc/systemd/system"

# Log file
LOG_FILE="$SCRIPT_DIR/mount-manager.log"

# Check if script is run with sudo
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run with sudo privileges.${NC}"
    exit 1
fi

# Logging function
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Reload systemd configuration
reload_systemd() {
    systemctl daemon-reload
    log_action "Reloaded systemd configuration"
}

# Validate mount file
validate_mount_file() {
    local mount_file="$1"
    # Basic validation, can be extended
    if grep -q "^\[Mount\]" "$mount_file" && grep -q "^What=" "$mount_file" && grep -q "^Where=" "$mount_file"; then
        return 0
    else
        return 1
    fi
}

# Check if target path exists
check_target_path() {
    local mount_file="$1"
    local target_path=$(grep "^Where=" "$mount_file" | cut -d'=' -f2)
    if [[ -d "$target_path" ]]; then
        return 0
    else
        return 1
    fi
}

# Check mount status
check_mount_status() {
    local mount_name="$1"
    if systemctl is-active --quiet "${mount_name}.mount"; then
        echo -e "${GREEN}active${NC}"
    elif ! validate_mount_file "$MOUNT_FILES_DIR/${mount_name}.mount" || ! check_target_path "$MOUNT_FILES_DIR/${mount_name}.mount"; then
        echo -e "${YELLOW}error${NC}"
    else
        echo -e "${RED}inactive${NC}"
    fi
}

# List available mounts
list_mounts() {
    local i=1
    echo "Available mounts:"
    for file in "$MOUNT_FILES_DIR"/*.mount; do
        if [[ -f "$file" ]]; then
            local mount_name=$(basename "$file" .mount)
            local status=$(check_mount_status "$mount_name")
            printf "%3d) %-20s [%s]\n" $i "$mount_name" "$status"
            ((i++))
        fi
    done
    echo -e "${YELLOW}q) Quit${NC}"
}

# Toggle mount status
toggle_mount() {
    local mount_name="$1"
    local source_file="$MOUNT_FILES_DIR/${mount_name}.mount"
    local systemd_file="$SYSTEMD_DIR/${mount_name}.mount"

    if ! validate_mount_file "$source_file"; then
        echo -e "${RED}Error: Invalid mount file for $mount_name${NC}"
        log_action "Failed to toggle mount: $mount_name (Invalid mount file)"
        return 1
    fi

    if ! check_target_path "$source_file"; then
        echo -e "${RED}Error: Target path does not exist for $mount_name${NC}"
        log_action "Failed to toggle mount: $mount_name (Target path does not exist)"
        return 1
    fi

    if systemctl is-active --quiet "${mount_name}.mount"; then
        systemctl stop "${mount_name}.mount"
        rm "$systemd_file"
        reload_systemd
        echo -e "${GREEN}Deactivated $mount_name${NC}"
        log_action "Deactivated mount: $mount_name"
    else
        cp "$source_file" "$systemd_file"
        reload_systemd
        systemctl start "${mount_name}.mount"
        echo -e "${GREEN}Activated $mount_name${NC}"
        log_action "Activated mount: $mount_name"
    fi
}

# Main menu
show_menu() {
    while true; do
        echo -e "\n${YELLOW}Mount Management Menu:${NC}"
        list_mounts
        echo -e "\nEnter the number of the mount to toggle its status, or 'q' to quit:"
        read -r choice

        case $choice in
            q)
                echo "Exiting..."
                break
                ;;
            [0-9]*)
                local i=1
                for file in "$MOUNT_FILES_DIR"/*.mount; do
                    if [[ -f "$file" && $i -eq $choice ]]; then
                        local mount_name=$(basename "$file" .mount)
                        toggle_mount "$mount_name"
                        break
                    fi
                    ((i++))
                done
                if [[ $i -le $choice ]]; then
                    echo -e "${RED}Invalid selection. Please try again.${NC}"
                fi
                ;;
            *)
                echo -e "${RED}Invalid input. Please enter a number or 'q'.${NC}"
                ;;
        esac
    done
}

# Main function
main() {
    if [[ ! -d "$MOUNT_FILES_DIR" ]]; then
        echo -e "${RED}Error: Mount files directory does not exist.${NC}"
        exit 1
    fi

    if [[ -z $(find "$MOUNT_FILES_DIR" -name "*.mount" -print -quit) ]]; then
        echo -e "${RED}Error: No .mount files found in $MOUNT_FILES_DIR${NC}"
        exit 1
    fi

    show_menu
}

main