#!/usr/bin/env bash

set -euo pipefail

# Konfiguration
readonly CONFIG_FILE="/etc/custom-mount-manager.conf"
readonly LOG_FILE="/var/log/custom-mounts.log"
readonly DEFAULT_MOUNT_BASE="/custom-mounts"

# Globale Variablen
MOUNT_BASE_DIR=""
SYSTEMD_MOUNT_FILES_DIR=""

# Farben für die Ausgabe
declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[1;33m'
    [BLUE]='\033[0;34m'
    [NC]='\033[0m' # No Color
)

# Funktionen

log() {
    local level="$1"
    local message="$2"
    echo "$(date "+%Y-%m-%d %H:%M:%S") [$level] $message" | sudo tee -a "$LOG_FILE" > /dev/null
}

print_color() {
    local color="$1"
    local message="$2"
    echo -e "${COLORS[$color]}$message${COLORS[NC]}"
}

error() {
    print_color "RED" "Fehler: $1" >&2
    log "ERROR" "$1"
    exit 1
}

check_sudo() {
    if [[ "$(id -u)" != "0" ]]; then
        error "Dieses Skript muss mit sudo-Rechten ausgeführt werden."
    fi
}

get_user_input() {
    local prompt="$1"
    local default="$2"
    local input
    read -rp "$prompt [$default]: " input
    echo "${input:-$default}"
}

validate_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        print_color "YELLOW" "Das Verzeichnis $dir existiert nicht. Soll es erstellt werden? (j/n)"
        read -r response
        if [[ "$response" =~ ^([jJ][aA]|[jJ])$ ]]; then
            sudo mkdir -p "$dir" || error "Konnte Verzeichnis $dir nicht erstellen."
            print_color "GREEN" "Verzeichnis $dir wurde erstellt."
        else
            error "Das Verzeichnis $dir existiert nicht und wurde nicht erstellt."
        fi
    fi
}

get_mount_directories() {
    SYSTEMD_MOUNT_FILES_DIR=$(dirname "$(readlink -f "$0")")
    print_color "YELLOW" "Das aktuelle Verzeichnis für Mount-Dateien ist: $SYSTEMD_MOUNT_FILES_DIR"
    local response
    read -rp "Ist dies das richtige Verzeichnis für die Mount-Dateien? (j/n): " response
    if [[ ! "$response" =~ ^([jJ][aA]|[jJ])$ ]]; then
        SYSTEMD_MOUNT_FILES_DIR=$(get_user_input "Gib das korrekte Verzeichnis mit den Mount-Dateien an" "$SYSTEMD_MOUNT_FILES_DIR")
    fi
    validate_directory "$SYSTEMD_MOUNT_FILES_DIR"

    MOUNT_BASE_DIR=$(get_user_input "Gib das Basis-Verzeichnis für die Mount-Punkte an" "$DEFAULT_MOUNT_BASE")
    validate_directory "$MOUNT_BASE_DIR"
}

create_edit_mount_file() {
    local action="$1"
    local mount_file

    if [[ "$action" == "edit" ]]; then
        print_color "YELLOW" "Verfügbare Mount-Dateien:"
        select mount_file in "$SYSTEMD_MOUNT_FILES_DIR"/*.mount; do
            if [[ -n "$mount_file" ]]; then
                break
            else
                print_color "RED" "Ungültige Auswahl. Bitte versuche es erneut."
            fi
        done
    else
        read -rp "Gib den Namen für die neue Mount-Datei ein: " mount_name
        mount_file="$SYSTEMD_MOUNT_FILES_DIR/${mount_name}.mount"
    fi

    local what
    local where
    local type
    local options

    if [[ "$action" == "edit" && -f "$mount_file" ]]; then
        what=$(grep "What=" "$mount_file" | cut -d'=' -f2)
        where=$(grep "Where=" "$mount_file" | cut -d'=' -f2)
        type=$(grep "Type=" "$mount_file" | cut -d'=' -f2)
        options=$(grep "Options=" "$mount_file" | cut -d'=' -f2)
    fi

    what=$(get_user_input "Gib die Quelle ein (What)" "${what:-}")
    where=$(get_user_input "Gib das Ziel ein (Where)" "${where:-$MOUNT_BASE_DIR/$(basename "$what")}")
    type=$(get_user_input "Gib den Dateisystemtyp ein" "${type:-auto}")
    options=$(get_user_input "Gib die Mount-Optionen ein" "${options:-defaults}")

    cat > "$mount_file" << EOF
[Unit]
Description=Mount for $where

[Mount]
What=$what
Where=$where
Type=$type
Options=$options

[Install]
WantedBy=multi-user.target
EOF

    print_color "GREEN" "Mount-Datei ${mount_file} wurde erstellt/aktualisiert."
}

create_edit_credentials() {
    local type="$1"
    local action="$2"
    local cred_file

    if [[ "$action" == "edit" ]]; then
        print_color "YELLOW" "Verfügbare Zugangsdaten-Dateien:"
        select cred_file in "$SYSTEMD_MOUNT_FILES_DIR"/*creds; do
            if [[ -n "$cred_file" ]]; then
                break
            else
                print_color "RED" "Ungültige Auswahl. Bitte versuche es erneut."
            fi
        done
    else
        read -rp "Gib den Namen für die neue Zugangsdaten-Datei ein: " cred_name
        cred_file="$SYSTEMD_MOUNT_FILES_DIR/${cred_name}.creds"
    fi

    if [[ "$type" == "smb" ]]; then
        local username
        local password
        if [[ "$action" == "edit" && -f "$cred_file" ]]; then
            username=$(grep "username=" "$cred_file" | cut -d'=' -f2)
            password=$(grep "password=" "$cred_file" | cut -d'=' -f2)
        fi
        username=$(get_user_input "Gib den Benutzernamen ein" "${username:-}")
        password=$(get_user_input "Gib das Passwort ein" "${password:-}")
        echo "username=$username" > "$cred_file"
        echo "password=$password" >> "$cred_file"
    elif [[ "$type" == "nfs" ]]; then
        local options
        if [[ "$action" == "edit" && -f "$cred_file" ]]; then
            options=$(cat "$cred_file")
        fi
        options=$(get_user_input "Gib die NFS-Optionen ein" "${options:-}")
        echo "$options" > "$cred_file"
    fi

    chmod 600 "$cred_file"
    print_color "GREEN" "Zugangsdaten-Datei ${cred_file} wurde erstellt/aktualisiert."
}

check_and_enable_mount() {
    local mount_file="$1"
    local mount_name
    mount_name=$(basename "$mount_file" .mount)
    
    print_color "YELLOW" "Prüfe $mount_name..."
    log "INFO" "Prüfe $mount_name"
    
    local mount_path
    local mount_source
    mount_path=$(grep "Where=" "$mount_file" | cut -d'=' -f2)
    mount_source=$(grep "What=" "$mount_file" | cut -d'=' -f2)
    
    if [[ -z "$mount_path" || -z "$mount_source" ]]; then
        error "Ungültige Konfiguration in $mount_file."
    fi
    
    sudo mkdir -p "$mount_path"
    sudo cp "$mount_file" /etc/systemd/system/
    
    if ! sudo systemctl is-enabled "$mount_name.mount" &>/dev/null; then
        if sudo systemctl enable "$mount_name.mount"; then
            print_color "GREEN" "$mount_name erfolgreich aktiviert."
            log "INFO" "$mount_name erfolgreich aktiviert"
        else
            error "Fehler beim Aktivieren von $mount_name."
        fi
    else
        print_color "YELLOW" "$mount_name ist bereits aktiviert."
        log "INFO" "$mount_name war bereits aktiviert"
    fi
    
    if sudo systemctl start "$mount_name.mount"; then
        print_color "GREEN" "$mount_name erfolgreich gestartet."
        log "INFO" "$mount_name erfolgreich gestartet"
    else
        error "Fehler beim Starten von $mount_name."
    fi
}

disable_and_remove_mount() {
    local mount_file="$1"
    local mount_name
    mount_name=$(basename "$mount_file" .mount)
    
    print_color "YELLOW" "Deaktiviere und entferne $mount_name..."
    log "INFO" "Deaktiviere und entferne $mount_name"
    
    sudo systemctl stop "$mount_name.mount"
    sudo systemctl disable "$mount_name.mount"
    sudo rm -f "/etc/systemd/system/$mount_name.mount"
    
    print_color "GREEN" "$mount_name erfolgreich deaktiviert und entfernt."
    log "INFO" "$mount_name erfolgreich deaktiviert und entfernt"
}

show_status() {
    print_color "YELLOW" "Status aller Custom Mounts:"
    log "INFO" "Status aller Custom Mounts abgefragt"
    local found_mounts=false
    while IFS= read -r -d '' mount_file; do
        found_mounts=true
        local mount_name
        mount_name=$(basename "$mount_file" .mount)
        if sudo systemctl is-active "$mount_name.mount" &>/dev/null; then
            print_color "GREEN" "$mount_name ist aktiv"
        else
            print_color "RED" "$mount_name ist inaktiv"
        fi
    done < <(find "$SYSTEMD_MOUNT_FILES_DIR" -maxdepth 1 -type f -name "*.mount" -print0)
    
    if [ "$found_mounts" = false ]; then
        print_color "YELLOW" "Keine Mount-Dateien im Verzeichnis $SYSTEMD_MOUNT_FILES_DIR gefunden."
    fi
}

main_menu() {
    while true; do
        echo
        print_color "BLUE" "Custom Mount Manager"
        echo "1. Aktiviere Mounts"
        echo "2. Deaktiviere Mounts"
        echo "3. Zeige Status"
        echo "4. Erstelle/Bearbeite Mount-Datei"
        echo "5. Erstelle/Bearbeite Zugangsdaten (SMB/NFS)"
        echo "6. Ändere Mount-Konfigurationen"
        echo "7. Beenden"
        local option
        option=$(get_user_input "Wähle eine Option (1-7)" "")
        
        case $option in
            1)
                sudo systemctl daemon-reload
                while IFS= read -r -d '' mount_file; do
                    check_and_enable_mount "$mount_file"
                done < <(find "$SYSTEMD_MOUNT_FILES_DIR" -maxdepth 1 -type f -name "*.mount" -print0)
                ;;
            2)
                while IFS= read -r -d '' mount_file; do
                    disable_and_remove_mount "$mount_file"
                done < <(find "$SYSTEMD_MOUNT_FILES_DIR" -maxdepth 1 -type f -name "*.mount" -print0)
                sudo systemctl daemon-reload
                ;;
            3)
                show_status
                ;;
            4)
                local action
                read -rp "Möchtest du eine neue Mount-Datei erstellen oder eine bestehende bearbeiten? (neu/bearbeiten): " action
                if [[ "$action" == "neu" ]]; then
                    create_edit_mount_file "create"
                elif [[ "$action" == "bearbeiten" ]]; then
                    create_edit_mount_file "edit"
                else
                    print_color "RED" "Ungültige Auswahl."
                fi
                ;;
            5)
                local cred_type
                local cred_action
                read -rp "Für welchen Typ möchtest du Zugangsdaten erstellen/bearbeiten? (smb/nfs): " cred_type
                read -rp "Möchtest du neue Zugangsdaten erstellen oder bestehende bearbeiten? (neu/bearbeiten): " cred_action
                if [[ "$cred_type" == "smb" || "$cred_type" == "nfs" ]] && [[ "$cred_action" == "neu" || "$cred_action" == "bearbeiten" ]]; then
                    create_edit_credentials "$cred_type" "$cred_action"
                else
                    print_color "RED" "Ungültige Auswahl."
                fi
                ;;
            6)
                get_mount_directories
                ;;
            7)
                print_color "GREEN" "Beende Programm."
                exit 0
                ;;
            *)
                print_color "RED" "Ungültige Option. Bitte wähle 1-7."
                ;;
        esac
    done
}

# Hauptprogramm
check_sudo
get_mount_directories
main_menu
