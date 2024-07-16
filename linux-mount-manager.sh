#!/bin/bash

# ============================================================================
# Mount Management Script
# Version: 1.1
# Last Updated: 2024-07-16
# Author: ben7sys
# GitHub: https://github.com/ben7sys
# ============================================================================

# Description:
# This script manages systemd mount units with improved error handling,
# user interaction, and custom mount support. It provides an interactive
# menu for activating, deactivating, and managing both standard and custom
# mount units.

# Usage:
# Run the script with sudo privileges:
#   sudo ./linux-mount-manager.sh

# Main features:
# - List all available mounts (mount files and existing custom mounts)
# - Activate and deactivate mounts
# - Display mount file contents
# - Handle errors (missing target directories, invalid mount files)
# - Manage custom mounts in systemd directory

# Changelog:
# v1.1 (2024-07-16)
# - Improved handling of custom mounts
# - Fixed color display issues in the menu
# - Enhanced error handling and user prompts
# - Optimized mount listing to avoid duplicates
# - Introduced color-coded status display
# - Added help function
# - Added support for custom mounts in systemd directory
# - Improved menu refresh logic

# v1.0 (2024-07-14)
# - Initial release of the revamped script


# ============================================================================
# Script starts here

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
    local systemd_file="$SYSTEMD_DIR/${mount_name}.mount"
    
    if [[ ! -f "$mount_file" && -f "$systemd_file" ]]; then
        mount_file="$systemd_file"
    fi
    
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
    local systemd_file="$SYSTEMD_DIR/${mount_name}.mount"
    
    if [[ ! -f "$mount_file" && -f "$systemd_file" ]]; then
        mount_file="$systemd_file"
    fi
    
    echo -e "\nDetails for $mount_name:"
    echo
    echo -e "Content of ${mount_name}.mount:"
    cat "$mount_file"
    echo
    if ! check_target_path "$mount_file"; then
        local target_path=$(grep "^Where=" "$mount_file" | cut -d'=' -f2)
        echo -e "${RED}Target path does not exist: $target_path${NC}"
        echo
    fi
    if ! validate_mount_file "$mount_file"; then
        echo -e "${RED}Invalid mount file. Missing required sections or fields.${NC}"
        echo
    fi
}

# Activate mount
activate_mount() {
    local mount_name="$1"
    local mount_file="$MOUNT_FILES_DIR/${mount_name}.mount"
    local systemd_file="$SYSTEMD_DIR/${mount_name}.mount"
    
    if [[ ! -f "$mount_file" && -f "$systemd_file" ]]; then
        echo -e "${YELLOW}This is a custom mount. Copying to script directory...${NC}"
        cp "$systemd_file" "$mount_file"
        log_action "Copied custom mount $mount_name to script directory"
    fi
    
    cp "$mount_file" "$systemd_file"
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
    local systemd_file="$SYSTEMD_DIR/${mount_name}.mount"
    local status=$(check_mount_status "$mount_name")

    if [[ ! -f "$mount_file" && -f "$systemd_file" ]]; then
        echo -e "${YELLOW}This is a custom mount (${systemd_file}).${NC}"
        echo -e "${YELLOW}Do you want to copy it to the script directory (${mount_file})? (y/n):${NC} "
        read -r answer
        if [[ $answer == "y" ]]; then
            cp "$systemd_file" "$mount_file"
            echo -e "${GREEN}Copied custom mount to script directory.${NC}"
            log_action "Copied custom mount $mount_name to script directory"
        else
            echo "Proceeding without copying."
        fi

        if [[ $status == "active" ]]; then
            echo -e "${YELLOW}This custom mount is currently active. Do you want to deactivate it? (y/n):${NC} "
            read -r deactivate_answer
            if [[ $deactivate_answer == "y" ]]; then
                deactivate_mount "$mount_name"
                return
            else
                echo "Mount will remain active."
                return
            fi
        fi
    fi

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

# Display mount file content
display_mount_file() {
    local mount_name="$1"
    local mount_file="$MOUNT_FILES_DIR/${mount_name}.mount"
    local systemd_file="$SYSTEMD_DIR/${mount_name}.mount"

    if [[ -f "$mount_file" ]]; then
        echo -e "\n${YELLOW}Content of $mount_name.mount:${NC}"
        cat "$mount_file"
    elif [[ -f "$systemd_file" ]]; then
        echo -e "\n${YELLOW}Content of $mount_name.mount (custom mount):${NC}"
        cat "$systemd_file"
    else
        echo -e "${RED}Mount file for $mount_name not found.${NC}"
    fi
}

# List all mounts
list_all_mounts() {
    local -A mount_map  # Associative array to store unique mounts

    # First, add all mounts from the script directory
    for file in "$MOUNT_FILES_DIR"/*.mount; do
        if [[ -f "$file" ]]; then
            local mount_name=$(basename "$file" .mount)
            mount_map["$mount_name"]="normal"
        fi
    done

    # Then, add custom mounts from the systemd directory, if they don't already exist
    for file in "$SYSTEMD_DIR"/*.mount; do
        if [[ -f "$file" ]]; then
            local mount_name=$(basename "$file" .mount)
            if [[ ! -v mount_map["$mount_name"] ]]; then
                mount_map["$mount_name"]="custom"
            fi
        fi
    done

    # Now list all unique mounts
    local i=1
    echo "Available mounts:"
    for mount_name in "${!mount_map[@]}"; do
        local mount_type="${mount_map[$mount_name]}"
        list_mount $i "$mount_name" "$mount_type"
        ((i++))
    done
}

# List a single mount
# Note: Use %b in printf to correctly interpret color codes
list_mount() {
    local index="$1"
    local mount_name="$2"
    local mount_type="$3"
    local status=$(check_mount_status "$mount_name")
    local type_indicator=""
    
    [[ "$mount_type" == "custom" ]] && type_indicator=" ${YELLOW}(custom)${NC}"
    
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
    
    printf "%3d) %-20s [%b]%b\n" "$index" "$mount_name" "$status_colored" "$type_indicator"
}

# Get mount name by index
get_mount_name_by_index() {
    local index="$1"
    local i=0
    local -A mount_map

    # Populate mount_map (same logic as in list_all_mounts)
    for file in "$MOUNT_FILES_DIR"/*.mount; do
        if [[ -f "$file" ]]; then
            local mount_name=$(basename "$file" .mount)
            mount_map["$mount_name"]="normal"
        fi
    done

    for file in "$SYSTEMD_DIR"/*.mount; do
        if [[ -f "$file" ]]; then
            local mount_name=$(basename "$file" .mount)
            if [[ ! -v mount_map["$mount_name"] ]]; then
                mount_map["$mount_name"]="custom"
            fi
        fi
    done

    for mount_name in "${!mount_map[@]}"; do
        if [[ $i -eq $index ]]; then
            echo "$mount_name"
            return 0
        fi
        ((i++))
    done

    return 1
}

# Show help
show_help() {
    echo -e "\n${YELLOW}Mount Management Help:${NC}"
    echo -e "This script helps you manage systemd mount units."
    echo -e "\nAvailable actions:"
    echo -e "  ${GREEN}[number]${NC} - Select a mount to toggle its status"
    echo -e "    If active: The mount will be deactivated"
    echo -e "    If inactive: The mount will be activated"
    echo -e "    If error: You'll be guided through fixing the issue"
    echo -e "  ${GREEN}d[number]${NC} - Display the content of the selected mount file"
    echo -e "  ${GREEN}h${NC} - Show this help message"
    echo -e "  ${GREEN}q${NC} - Quit the program"
    echo -e "\nMount status:"
    echo -e "  ${GREEN}active${NC} - The mount is currently active and in use"
    echo -e "  ${RED}inactive${NC} - The mount is currently not active"
    echo -e "  ${YELLOW}error${NC} - There's an issue, such as missing target directory or invalid file"
    echo -e "\n${YELLOW}Custom mounts:${NC}"
    echo -e "  Mounts marked with (custom) exist in the systemd directory but not in the script directory."
    echo -e "  You can manage these, but you'll be asked if you want to copy them to the script directory."
    echo -e "\nPress Enter to return to the main menu..."
    read -r
}

# Show menu
show_menu() {
    local refresh=true
    local -A mount_map
    while true; do
        if $refresh; then
            clear  # Clear the screen before showing the menu
            echo -e "\n${YELLOW}Mount Management Menu:${NC}"
            
            # Generate a fresh list of mounts
            list_all_mounts
            
            echo -e "\nActions:"
            echo -e "  ${GREEN}[number]${NC} Toggle mount status (activate/deactivate)"
            echo -e "  ${GREEN}d[number]${NC} Display mount file content"
            echo -e "  ${GREEN}h${NC} Show help"
            echo -e "  ${GREEN}q${NC} Quit the program"
            echo -e "\nStatus colors:"
            echo -e "  ${GREEN}active${NC} - Mount is currently active"
            echo -e "  ${RED}inactive${NC} - Mount is currently inactive"
            echo -e "  ${YELLOW}error${NC} - There's an issue with the mount"
            echo -e "\n${YELLOW}Custom mounts${NC} are indicated with (custom)"
        fi

        refresh=false  # Set to false by default
        echo -e "\nEnter your choice:"
        read -r choice

        case $choice in
            q)
                echo "Exiting..."
                return
                ;;
            h)
                show_help
                refresh=true
                ;;
            d[0-9]*)
                local index=$((${choice#d} - 1))
                local mount_name=$(get_mount_name_by_index "$index")
                if [[ -n "$mount_name" ]]; then
                    display_mount_file "$mount_name"
                    echo -e "\nPress Enter to continue..."
                    read -r
                    refresh=true
                else
                    echo -e "${RED}Invalid selection. Please try again.${NC}"
                fi
                ;;
            [0-9]*)
                local mount_name=$(get_mount_name_by_index "$((choice - 1))")
                if [[ -n "$mount_name" ]]; then
                    toggle_mount "$mount_name"
                    refresh=true
                else
                    echo -e "${RED}Invalid selection. Please try again.${NC}"
                fi
                ;;
            *)
                echo -e "${RED}Invalid input. Please enter a number, 'd' followed by a number, 'h', or 'q'.${NC}"
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

    if [[ -z $(find "$MOUNT_FILES_DIR" -name "*.mount" -print -quit) && -z $(find "$SYSTEMD_DIR" -name "*.mount" -print -quit) ]]; then
        echo -e "${RED}Error: No .mount files found in $MOUNT_FILES_DIR or $SYSTEMD_DIR${NC}"
        exit 1
    fi

    show_menu
}

main