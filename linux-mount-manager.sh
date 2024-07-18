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

# Script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
MOUNT_FILES_DIR="$SCRIPT_DIR"
SYSTEMD_DIR="/etc/systemd/system"

# Check if script is run with sudo
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run with sudo privileges.${NC}"
    exit 1
fi

# Log file
LOG_FILE="$SCRIPT_DIR/linux-mount-manager.log"

# Error message handling
error_message() {
    local message="$1"
    echo -e "${RED}${message}${NC}"
    log_action "${message}"
}

# Logging function
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Check mount files directory
: <<'COMMENT'
Checks user defined mount files directory
check_user_mount_files_exist - Check if the mount files directory 
defined by the user exists and contains .mount files.
COMMENT
check_user_mount_files_exist() {
    if [[ ! -d "$MOUNT_FILES_DIR" ]]; then
        echo -e "${RED}Error: Mount files directory does not exist.${NC}"
        exit 1
    fi

    if [[ -z $(find "$MOUNT_FILES_DIR" -name "*.mount" -print -quit) && -z $(find "$SYSTEMD_DIR" -name "*.mount" -print -quit) ]]; then
        echo -e "${RED}Error: No .mount files found in $MOUNT_FILES_DIR or $SYSTEMD_DIR${NC}"
        exit 1
    fi
}

# Reload systemd configuration
: <<'COMMENT'
Reload systemd configuration
reload_systemd - Reloads the systemd configuration to apply any changes made to unit files.
This function does not depend on other functions but is called after
modifications to systemd unit files to ensure changes are recognized.
COMMENT
reload_systemd_if_needed() {
    if [[ "$NEED_RELOAD" == true ]]; then
        systemctl daemon-reload
        log_action "Reloaded systemd configuration"
    fi
}

# Function to activate a mount
: <<'COMMENT'
Activates a specified mount by name.
This function checks if the mount file exists, copies it to the systemd directory if necessary, and sets the correct permissions.
It then reloads the systemd configuration and attempts to start the mount.
If the mount is successfully activated, it optionally enables the mount to be automatic at boot based on user input.
Logs actions and provides feedback based on success or failure.
Dependencies:
- Variables: $MOUNT_FILES_DIR
- Functions: log_action
- Commands: systemctl, cp, chmod, cmp, read
COMMENT
activate_mount() {
    local mount_name="$1"
    local mount_file="$MOUNT_FILES_DIR/${mount_name}.mount"
    local systemd_file="/etc/systemd/system/${mount_name}.mount"
    NEED_RELOAD=false
    
    # Check if the mount file exists and throw an error if it doesn't
    if [[ ! -f "$mount_file" ]]; then
        error_message "Error: Mount file for $mount_name not found in $MOUNT_FILES_DIR"
        return 1
    fi

    # Copy the mount file to systemd directory if it doesn't exist or if it's different
    if [[ ! -f "$systemd_file" || ! $(cmp -s "$mount_file" "$systemd_file") ]]; then
        cp "$mount_file" "$systemd_file"
        chmod 644 "$systemd_file"
        NEED_RELOAD=true
        echo -e "${YELLOW}Copied $mount_name.mount to /etc/systemd/system/${NC}"
        log_action "Copied mount file for $mount_name to systemd directory"
    fi

    # Reload systemd to recognize any changes
    reload_systemd_if_needed

    # Try to start the mount
    if systemctl start "${mount_name}.mount"; then
        echo -e "${GREEN}Successfully activated $mount_name${NC}"
        log_action "Activated mount: $mount_name"
        
        # Check if the mount should be enabled at boot
        echo -e "${YELLOW}Do you want to enable $mount_name to mount automatically at boot? (y/n)${NC}"
        read -r enable_at_boot
        if [[ "$enable_at_boot" == "y" ]]; then
            if systemctl enable "${mount_name}.mount"; then
                echo -e "${GREEN}$mount_name will now mount automatically at boot${NC}"
                log_action "Enabled $mount_name for automatic mounting at boot"
            else
                error_message "Failed to enable $mount_name for automatic mounting at boot"
            fi
        fi
        
        return 0
    else
        error_message "Failed to activate $mount_name"
                
        # Check the mount status for more information
        local mount_status=$(systemctl status "${mount_name}.mount")
        echo -e "${YELLOW}Mount status:${NC}"
        echo "$mount_status"
        
        return 1
    fi
}

# Deactivate mount
: <<'COMMENT'
Deactivates a specified mount by name.
This function checks if the mount point is currently in use and provides an error message if it is.
If not in use, it stops and disables the mount and automount services, removes the corresponding systemd files, and reloads the systemd configuration.
Logs actions and provides feedback based on success or failure.
Dependencies:
- Variables: $SYSTEMD_DIR
- Functions: log_action, reload_systemd
- Commands: grep, cut, fuser, systemctl, rm
COMMENT
deactivate_mount() {
    local mount_name="$1"
    local systemd_file="$SYSTEMD_DIR/${mount_name}.mount"
    local automount_file="$SYSTEMD_DIR/${mount_name}.automount"
    local mount_point=$(grep "^Where=" "$systemd_file" | cut -d'=' -f2)
    
    # Check if the mount is currently in use
    if fuser -sm "$mount_point" > /dev/null 2>&1; then
        error_message "ERROR: Cannot deactivate $mount_name. It is currently in use."
        echo -e "${YELLOW}Please close all applications using this mount and try again.${NC}"
        echo -e "You can use 'fuser -m $mount_point' to see which processes are using the mount."
        log_action "Failed to deactivate mount: $mount_name (in use)"
        return 1
    fi

    # Stop and disable the mount and automount services
    systemctl stop "${mount_name}.mount" "${mount_name}.automount" 2>/dev/null
    systemctl disable "${mount_name}.mount" "${mount_name}.automount" 2>/dev/null
    rm -f "$systemd_file" "$automount_file"
    NEED_RELOAD=true
    reload_systemd_if_needed
    echo -e "${GREEN}Successfully deactivated $mount_name${NC}"
    log_action "Deactivated mount: $mount_name"
    return 0
}

# Automatically create and enable automount for a given mount
: <<'COMMENT'
Automatically creates and enables an automount for a given mount.
This function generates an automount file based on the mount file, 
reloads the systemd configuration, and starts the automount service.
It verifies if the automount service is active and logs the result.
Dependencies:
- Variables: $SYSTEMD_DIR
- Functions: log_action
- Commands: grep, cut, systemctl
COMMENT
create_automount_file() {
    local mount_name="$1"
    local automount_file="$SYSTEMD_DIR/${mount_name}.automount"
    local mount_file="$SYSTEMD_DIR/${mount_name}.mount"
    
    echo "[Unit]
Description=Automount for $mount_name

[Automount]
Where=$(grep '^Where=' "$mount_file" | cut -d'=' -f2)

[Install]
WantedBy=multi-user.target" > "$automount_file"

    NEED_RELOAD=true
    reload_systemd_if_needed
    systemctl enable "${mount_name}.automount"
    systemctl start "${mount_name}.automount"
    
    if systemctl is-active --quiet "${mount_name}.automount"; then
        echo -e "${GREEN}Automount for $mount_name is active${NC}"
        log_action "Created and enabled automount for $mount_name"
    else
        error_message "Failed to activate automount for $mount_name"
    fi
}

# Check mount status
# Function to check the status of a mount
: <<'COMMENT'
Checks the status of a specified mount by name.
This function verifies the existence of mount and automount files, 
checks if the mount is active and enabled at boot, and ensures correct file placement and permissions.
It returns the status as "active" or "inactive" along with additional 
information like "on-demand", "startup", "not_in_systemd", and "wrong_permissions".
Dependencies:
- Variables: $MOUNT_FILES_DIR
- Commands: systemctl, stat
COMMENT
check_mount_status() {
    local mount_name="$1"
    local status=""
    local additional_info=""
    local mount_file="$MOUNT_FILES_DIR/${mount_name}.mount"
    local automount_file="$MOUNT_FILES_DIR/${mount_name}.automount"
    local systemd_mount_file="/etc/systemd/system/${mount_name}.mount"
    local systemd_automount_file="/etc/systemd/system/${mount_name}.automount"

    # Check if the mount files exist in the script directory
    if [[ ! -f "$mount_file" && ! -f "$automount_file" ]]; then
        echo "error,no_config"
        return 1
    fi

    # Check if the mount is active
    if systemctl is-active "${mount_name}.mount" >/dev/null 2>&1; then
        status="active"
    else
        status="inactive"
    fi

    # Check if automount is set up
    if [[ -f "$automount_file" && systemctl is-active "${mount_name}.automount" >/dev/null 2>&1 ]]; then
        additional_info="on-demand"
    fi

    # Check if mount is enabled at boot
    if systemctl is-enabled "${mount_name}.mount" >/dev/null 2>&1; then
        [[ -z "$additional_info" ]] && additional_info="startup" || additional_info="${additional_info},startup"
    fi

    # Check if automount is enabled at boot
    if systemctl is-enabled "${mount_name}.automount" >/dev/null 2>&1; then
        [[ -z "$additional_info" ]] && additional_info="on-demand" || additional_info="${additional_info},on-demand"
    fi

    # Check if mount files are correctly placed in /etc/systemd/system/
    if [[ -f "$mount_file" && ! -f "$systemd_mount_file" ]]; then
        additional_info="${additional_info:+$additional_info,}not_in_systemd"
    fi
    
    # Check if automount files are correctly placed in /etc/systemd/system/
    if [[ -f "$automount_file" && ! -f "$systemd_automount_file" ]]; then
        additional_info="${additional_info:+$additional_info,}not_in_systemd"
    fi

    # Check file permissions
    if [[ -f "$systemd_mount_file" && $(stat -c %a "$systemd_mount_file") != "644" ]]; then
        additional_info="${additional_info:+$additional_info,}wrong_permissions"
    fi
    if [[ -f "$systemd_automount_file" && $(stat -c %a "$systemd_automount_file") != "644" ]]; then
        additional_info="${additional_info:+$additional_info,}wrong_permissions"
    fi

    # Return the status and additional info
    echo "${status},${additional_info}"
}

# Display mount file content
: <<'COMMENT'
Displays the content of a specified mount file by name.
This function checks if the mount file exists in the script directory and displays its content.
If the mount file does not exist in the script directory, 
it checks the systemd directory and displays it if found.
Outputs an error message if the mount file is not found.
Dependencies:
- Variables: $MOUNT_FILES_DIR, $SYSTEMD_DIR
- Commands: cat
COMMENT
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
        error_message "Mount file for $mount_name not found."
    fi
}

# Function to toggle the status of a mount
: <<'COMMENT'
Toggles the state of a specified mount by name, either activating or deactivating it based on its current status.
This function first checks the mount status and then prompts the user with options to activate or deactivate the mount with different methods.
Handles custom mounts, allowing the user to copy them to the script directory.
Logs actions and provides feedback based on user choices and operation success.
Dependencies:
- Variables: $MOUNT_FILES_DIR, $SYSTEMD_DIR
- Functions: check_mount_status, log_action, deactivate_mount, activate_mount, create_automount_file
- Commands: cp, read, systemctl
COMMENT
toggle_mount() {
    local mount_name="$1"
    local mount_file="$MOUNT_FILES_DIR/${mount_name}.mount"
    local systemd_file="$SYSTEMD_DIR/${mount_name}.mount"
    local status=$(check_mount_status "$mount_name")

    # Check if it's a custom mount (exists only in systemd directory)
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
    fi

    # Extract status and additional info
    case $status in
        "active")
            echo -e "${YELLOW}Deactivating $mount_name...${NC}"
            echo -e "Choose deactivation option:"
            echo -e "1) Unmount immediately"
            echo -e "2) Disable automount"
            echo -e "3) Disable mount at system startup"
            echo -e "4) Cancel"
            read -r deactivate_choice

            case $deactivate_choice in
                1)
                    if ! deactivate_mount "$mount_name"; then
                        return 1
                    fi
                    ;;
                2)
                    systemctl disable "${mount_name}.automount"
                    echo -e "${GREEN}Disabled automount for $mount_name${NC}"
                    log_action "Disabled automount for $mount_name"
                    ;;
                3)
                    systemctl disable "${mount_name}.mount"
                    echo -e "${GREEN}Disabled automatic mounting at system startup for $mount_name${NC}"
                    log_action "Disabled automatic mounting at system startup for $mount_name"
                    ;;
                4)
                    echo "Operation cancelled."
                    return 1
                    ;;
                *)
                    error_message "Invalid choice. Operation cancelled."
                    return 1
                    ;;
            esac
            ;;
        "inactive" | "automount" | "enabled")
            echo -e "${YELLOW}Activating $mount_name...${NC}"
            echo -e "Choose activation option:"
            echo -e "1) Mount immediately"
            echo -e "2) Set up automount (on-demand)"
            echo -e "3) Mount automatically at system startup"
            echo -e "4) Cancel"
            read -r activate_choice

            # Activate the mount based on user choice
            case $activate_choice in
                1)
                    if ! activate_mount "$mount_name"; then
                        return 1
                    fi
                    ;;
                2)
                    create_automount_file "$mount_name"
                    ;;
                3)
                    if systemctl enable "${mount_name}.mount"; then
                        echo -e "${GREEN}$mount_name will be mounted automatically at system startup${NC}"
                        log_action "Enabled $mount_name for automatic mounting at system startup"
                    else
                        error_message "Failed to enable $mount_name for automatic mounting"
                        return 1
                    fi
                    ;;
                4)
                    echo "Operation cancelled."
                    return 1
                    ;;
                *)
                    error_message "Invalid choice. Operation cancelled."
                    return 1
                    ;;
            esac
            ;;
        *)
            error_message "Error: Unknown mount status for $mount_name"
            return 1
            ;;
    esac
    
    return 0
}

# List all mounts
: <<'COMMENT'
Lists all available mounts by checking both the script directory and the systemd directory.
This function uses an associative array to store unique mounts, ensuring no duplicates.
It first adds mounts from the script directory, then adds custom mounts from the systemd directory 
if they don't already exist in the array.
Finally, it lists all unique mounts with their type - normal or custom.
Dependencies:
- Variables: $MOUNT_FILES_DIR, $SYSTEMD_DIR
- Functions: list_mount
- Commands: basename
COMMENT
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
: <<'COMMENT'
list_mount - Displays detailed information about a specific mount in a formatted list.
This function takes the index, mount name, and mount type as input, 
checks the mount status, and displays the status along with additional information and type indicator.
The status is color-coded: green for active, red for inactive, blue for automount, and yellow for other statuses.
Additional information is also color-coded: cyan for startup and magenta for on-demand.
Dependencies:
- Variables: $GREEN, $RED, $BLUE, $YELLOW, $CYAN, $MAGENTA, $NC
- Functions: check_mount_status
- Commands: cut, printf
COMMENT
list_mount() {
    local index="$1"
    local mount_name="$2"
    local mount_type="$3"
    local status_info=$(check_mount_status "$mount_name")
    local status=$(echo "$status_info" | cut -d',' -f1)
    local additional_info=$(echo "$status_info" | cut -d',' -f2)
    local type_indicator=""
    
    [[ "$mount_type" == "custom" ]] && type_indicator=" ${YELLOW}(custom)${NC}"
    
    case $status in
        "active")
            status_colored="${GREEN}active${NC}"
            ;;
        "inactive")
            status_colored="${RED}inactive${NC}"
            ;;
        "automount")
            status_colored="${BLUE}automount${NC}"
            ;;
        *)
            status_colored="${YELLOW}$status${NC}"
            ;;
    esac

    case $additional_info in
        "startup")
            additional_info_colored="${CYAN}(startup)${NC}"
            ;;
        "on-demand")
            additional_info_colored="${MAGENTA}(on-demand)${NC}"
            ;;
        *)
            additional_info_colored=""
            ;;
    esac
    
    printf "%3d) %-20s [%-10b] %-15b%b\n" "$index" "$mount_name" "$status_colored" "$additional_info_colored" "$type_indicator"
}

# Get mount name by index
: <<'COMMENT'
get_mount_name_by_index - Retrieves the mount name based on a given index.
This function populates an associative array with all mounts 
from both the script directory and the systemd directory.
It iterates through the array and returns the mount name that corresponds to the provided index.
Dependencies:
- Variables: $MOUNT_FILES_DIR, $SYSTEMD_DIR
- Commands: basename, echo
COMMENT
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
: <<'COMMENT'
show_help - Displays a help message for the mount management script.
This function provides an overview of the script's functionality, 
available actions, mount statuses, and explanations of custom mounts.
The help message is color-coded for better readability and prompts the user 
to press Enter to return to the main menu.
Dependencies:
- Variables: $YELLOW, $GREEN, $RED, $NC
- Commands: echo, read
COMMENT
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

# Function to display the main menu
: <<'COMMENT'
show_menu - Displays the main menu for the mount management script.
This function continuously displays a refreshed menu with a list of all 
mounts and available actions until the user decides to quit.
It clears the screen, generates a fresh list of mounts, 
and shows the status colors and action options.
The user is prompted for input to perform actions such as toggling mount status, 
displaying mount file content, showing help, or quitting the program.
Dependencies:
- Variables: $YELLOW, $GREEN, $RED, $NC
- Functions: list_all_mounts, show_help
- Commands: clear, echo, read
COMMENT
show_menu() {
    local refresh=true # Flag to refresh the menu
    local -A mount_map  # Declare an associative array to store mount information

    while true; do
        if $refresh; then
            clear  # Clear the screen before displaying the menu
            echo -e "\n${YELLOW}Mount Management Menu:${NC}"
            
            # Generate a fresh list of all mounts
            list_all_mounts
            
            # Display available actions
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

        refresh=false  # Set refresh to false, will be set to true when needed

        # Prompt user for input
        echo -e "\nEnter your choice:"
        read -r choice

        # Process user input
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
                # Extract the number after 'd' and subtract 1 (as indexing starts at 0)
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
                # Get the mount name based on the entered number
                local mount_name=$(get_mount_name_by_index "$((choice - 1))")
                if [[ -n "$mount_name" ]]; then
                    if toggle_mount "$mount_name"; then
                        refresh=true
                    else
                        echo -e "\nPress Enter to continue..."
                        read -r
                        refresh=true
                    fi
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
: <<'COMMENT'
main - Entry point for the mount management script.
This function checks if the mount files directory exists and verifies the presence of .mount files in the specified directories.
If the required conditions are met, it calls the show_menu function to display the main menu.
Dependencies:
- Variables: $MOUNT_FILES_DIR, $SYSTEMD_DIR, $RED, $NC
- Functions: show_menu
- Commands: echo, exit, find
COMMENT
main() {
    check_user_mount_files_exist
    show_menu
}

main




############################################################################################################
# additional functions actually not used in the main script
############################################################################################################

# Validate mount file
: <<'COMMENT'
Validates the structure of the mount file.
This function checks if the mount file contains the required sections and fields: '[Mount]', 'What=', and 'Where='.
Returns 0 if the mount file is valid, otherwise returns 1.
Dependencies:
- Commands: grep
COMMENT
validate_mount_file() {
    local mount_file="$1"
    if grep -q "^\[Mount\]" "$mount_file" && grep -q "^What=" "$mount_file" && grep -q "^Where=" "$mount_file"; then
        return 0
    else
        return 1
    fi
}

# Check if target path exists
: <<'COMMENT'
Checks if the target path specified in the mount file exists.
This function depends on a valid mount file being provided, and extracts
the target path from the 'Where=' entry in the mount file.
Returns 0 if the target path exists, otherwise returns 1.
Dependencies:
- Commands: grep, cut
COMMENT
check_target_path() {
    local mount_file="$1"
    local target_path=$(grep "^Where=" "$mount_file" | cut -d'=' -f2)
    if [[ -d "$target_path" ]]; then
        return 0
    else
        return 1
    fi
}



# Show mount details
: <<'COMMENT'
Displays detailed information about a specified mount by name.
This function shows the content of the mount file and verifies the existence of the target path and the validity of the mount file.
It outputs relevant messages if the target path does not exist or if the mount file is invalid.
Dependencies:
- Variables: $MOUNT_FILES_DIR, $SYSTEMD_DIR
- Functions: check_target_path, validate_mount_file
COMMENT
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











