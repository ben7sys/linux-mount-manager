#!/bin/bash

# Mount Management Script
# Version: 2.2
# This script manages systemd mount units with improved error handling and user interaction.

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
    local mount_file="$MOUNT_FILES_DIR/${mount_name}.mount"
    if systemctl is-active --quiet "${mount_name}.mount"; then
        echo "active"
    elif ! validate_mount_file "$mount_file"; then
        echo "error (invalid file)"
    elif ! check_target_path "$mount_file"; then
        echo "error (missing target)"
    else
        echo "inactive"
    fi
}

# Show mount details
show_mount_details() {
    local mount_name="$1"
    local mount_file="$MOUNT_FILES_DIR/${mount_name}.mount"
    echo -e "\nDetails for $mount_name:"
    echo  # Add an empty line here
    echo -e "Content of ${mount_name}.mount:"
    cat "$mount_file"
    echo  # Add an empty line here
    if ! check_target_path "$mount_file"; then
        local target_path=$(grep "^Where=" "$mount_file" | cut -d'=' -f2)
        echo -e "${RED}Target path does not exist: $target_path${NC}"
        echo  # Add an empty line here
    fi
    if ! validate_mount_file "$mount_file"; then
        echo -e "${RED}Invalid mount file. Missing required sections or fields.${NC}"
        echo  # Add an empty line here
    fi
}

# Activate mount
activate_mount() {
    local mount_name="$1"
    local systemd_file="$SYSTEMD_DIR/${mount_name}.mount"
    cp "$MOUNT_FILES_DIR/${mount_name}.mount" "$systemd_file"
    reload_systemd
    if systemctl start "${mount_name}.mount"; then
        echo -e "${GREEN}Successfully activated $mount_name${NC}"
        log_action "Activated mount: $mount_name"
    else
        echo -e "${RED}Failed to activate $mount_name${NC}"
        log_action "Failed to activate mount: $mount_name"
    fi
}
# Deactivate mount
deactivate_mount() {
    local mount_name="$1"
    local systemd_file="$SYSTEMD_DIR/${mount_name}.mount"
    local mount_point=$(grep "^Where=" "$systemd_file" | cut -d'=' -f2)
    
    if fuser -sm "$mount_point" > /dev/null 2>&1; then
        echo -e "${RED}Cannot deactivate $mount_name. It is currently in use.${NC}"
        echo "Please close all applications using this mount and try again."
        log_action "Failed to deactivate mount: $mount_name (in use)"
        return 1
    fi

    if systemctl stop "${mount_name}.mount"; then
        rm "$systemd_file"
        reload_systemd
        echo -e "${GREEN}Successfully deactivated $mount_name${NC}"
        log_action "Deactivated mount: $mount_name"
    else
        echo -e "${RED}Failed to deactivate $mount_name${NC}"
        log_action "Failed to deactivate mount: $mount_name"
    fi
}

# Toggle mount
toggle_mount() {
    local mount_name="$1"
    local mount_file="$MOUNT_FILES_DIR/${mount_name}.mount"
    local status=$(check_mount_status "$mount_name")

    case $status in
        "error (missing target)")
            show_mount_details "$mount_name"
            local target_path=$(grep "^Where=" "$mount_file" | cut -d'=' -f2)
            echo -e "${YELLOW}The target directory does not exist. Do you want to create '$target_path'? (y/n):${NC} "
            read -r answer
            if [[ $answer == "y" ]]; then
                if mkdir -p "$target_path"; then
                    echo -e "${GREEN}Created directory: $target_path${NC}"
                    log_action "Created directory: $target_path"
                    activate_mount "$mount_name"
                else
                    echo -e "${RED}Failed to create directory. Please check permissions and try again.${NC}"
                    log_action "Failed to create directory: $target_path"
                fi
            else
                echo "Operation cancelled."
            fi
            ;;
        "error (invalid file)")
            show_mount_details "$mount_name"
            echo -e "${RED}The mount file is invalid. Please edit it to fix the issues.${NC}"
            read -p "Do you want to open the file in an editor now? (y/n): " answer
            if [[ $answer == "y" ]]; then
                ${EDITOR:-nano} "$mount_file"
                echo "Checking the updated mount file..."
                if validate_mount_file "$mount_file"; then
                    echo -e "${GREEN}Mount file has been successfully updated.${NC}"
                    log_action "Updated mount file: $mount_name"
                    activate_mount "$mount_name"
                else
                    echo -e "${RED}Mount file is still invalid. Please check and try again.${NC}"
                    log_action "Failed to update mount file: $mount_name"
                fi
            else
                echo "Operation cancelled."
            fi
            ;;
        "active")
            echo -e "${YELLOW}Deactivating $mount_name...${NC}"
            deactivate_mount "$mount_name"
            ;;
        "inactive")
            echo -e "${YELLOW}Activating $mount_name...${NC}"
            activate_mount "$mount_name"
            ;;
    esac
}

# List available mounts
list_mounts() {
    local i=1
    echo "Available mounts:"
    for file in "$MOUNT_FILES_DIR"/*.mount; do
        if [[ -f "$file" ]]; then
            local mount_name=$(basename "$file" .mount)
            local status=$(check_mount_status "$mount_name")
            case $status in
                "active")
                    status_colored="${GREEN}active${NC}"
                    ;;
                "inactive")
                    status_colored="${RED}inactive${NC}"
                    ;;
                *)
                    status_colored="${YELLOW}$status${NC}"
                    ;;
            esac
            printf "%3d) %-20s [%b]\n" $i "$mount_name" "$status_colored"
            ((i++))
        fi
    done
    echo -e "${YELLOW}q) Quit${NC}"
}

# Show menu
show_menu() {
    while true; do
        echo -e "\n${YELLOW}Mount Management Menu:${NC}"
        list_mounts
        echo -e "\nEnter the number of the mount to manage it, or 'q' to quit:"
        read -r choice

        case $choice in
            q)
                echo "Exiting..."
                return
                ;;
            [0-9]*)
                local selected=false
                local i=1
                for file in "$MOUNT_FILES_DIR"/*.mount; do
                    if [[ -f "$file" && $i -eq $choice ]]; then
                        local mount_name=$(basename "$file" .mount)
                        toggle_mount "$mount_name"
                        selected=true
                        break
                    fi
                    ((i++))
                done
                if ! $selected; then
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