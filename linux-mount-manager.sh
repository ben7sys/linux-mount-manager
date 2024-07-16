#!/bin/bash

# Systemd Mount Manager
# Verwaltet systemd Mount-Units für verschiedene Dateisysteme

set -euo pipefail

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging-Funktion
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${message}" >> /var/log/custom-mounts.log
    case $level in
        "INFO")  echo -e "${GREEN}${message}${NC}" ;;
        "WARN")  echo -e "${YELLOW}${message}${NC}" ;;
        "ERROR") echo -e "${RED}${message}${NC}" ;;
        *)       echo -e "${message}" ;;
    esac
}

# Überprüfung der sudo-Rechte
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Dieses Skript muss mit sudo-Rechten ausgeführt werden."
        exit 1
    fi
}

# Konfigurationsdatei lesen
read_config() {
    local config_file="./mount_manager.conf"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    else
        MOUNT_FILES_DIR="/etc/systemd/system"
        MOUNT_TARGET_DIR="/mnt"
        echo "MOUNT_FILES_DIR=\"$MOUNT_FILES_DIR\"" > "$config_file"
        echo "MOUNT_TARGET_DIR=\"$MOUNT_TARGET_DIR\"" >> "$config_file"
    fi
}

# Hauptmenü anzeigen
show_main_menu() {
    echo "=== Systemd Mount Manager ==="
    echo "1) Mounts verwalten"
    echo "2) Zugangsdaten verwalten"
    echo "3) Konfiguration verwalten"
    echo "4) Beenden"
    echo "Wählen Sie eine Option (1-4):"
}

# Mounts verwalten
manage_mounts() {
    while true; do
        echo "=== Mounts verwalten ==="
        local mounts=($(ls ${MOUNT_FILES_DIR}/*.mount 2>/dev/null))
        local statuses=$(systemctl is-active "${mounts[@]##*/}" 2>/dev/null)
        local i=0
        for mount in "${mounts[@]}"; do
            local mount_name=$(basename "$mount")
            local status=$(echo "$statuses" | sed -n "$((i+1))p")
            if [[ "$status" == "active" ]]; then
                echo -e "${GREEN}$((i+1))) ${mount_name}${NC}"
            else
                echo -e "${RED}$((i+1))) ${mount_name}${NC}"
            fi
            ((i++))
        done
        echo "A) Alle aktivieren"
        echo "D) Alle deaktivieren"
        echo "N) Neuen Mount erstellen"
        echo "Z) Zurück zum Hauptmenü"
        read -r -p "Wählen Sie eine Option: " choice
        case $choice in
            [1-9]*)
                if ((choice <= ${#mounts[@]})); then
                    toggle_mount "${mounts[$((choice-1))]}"
                else
                    log "WARN" "Ungültige Auswahl."
                fi
                ;;
            A|a) activate_all_mounts ;;
            D|d) deactivate_all_mounts ;;
            N|n) create_new_mount ;;
            Z|z) break ;;
            *) log "WARN" "Ungültige Option." ;;
        esac
    done
}

# Mount aktivieren/deaktivieren
toggle_mount() {
    local mount_file="$1"
    local mount_name=$(basename "$mount_file")
    local status=$(systemctl is-active "$mount_name" 2>/dev/null)
    if [[ "$status" == "active" ]]; then
        if systemctl stop "$mount_name" && systemctl disable "$mount_name"; then
            log "INFO" "$mount_name deaktiviert."
        else
            log "ERROR" "Fehler beim Deaktivieren von $mount_name."
        fi
    else
        if systemctl start "$mount_name" && systemctl enable "$mount_name"; then
            log "INFO" "$mount_name aktiviert."
        else
            log "ERROR" "Fehler beim Aktivieren von $mount_name."
        fi
    fi
}

# Alle Mounts aktivieren
activate_all_mounts() {
    local success=true
    for mount in ${MOUNT_FILES_DIR}/*.mount; do
        if ! systemctl start "$(basename "$mount")" || ! systemctl enable "$(basename "$mount")"; then
            log "ERROR" "Fehler beim Aktivieren von $(basename "$mount")."
            success=false
        fi
    done
    if $success; then
        log "INFO" "Alle Mounts aktiviert."
    else
        log "WARN" "Einige Mounts konnten nicht aktiviert werden."
    fi
}

# Alle Mounts deaktivieren
deactivate_all_mounts() {
    local success=true
    for mount in ${MOUNT_FILES_DIR}/*.mount; do
        if ! systemctl stop "$(basename "$mount")" || ! systemctl disable "$(basename "$mount")"; then
            log "ERROR" "Fehler beim Deaktivieren von $(basename "$mount")."
            success=false
        fi
    done
    if $success; then
        log "INFO" "Alle Mounts deaktiviert."
    else
        log "WARN" "Einige Mounts konnten nicht deaktiviert werden."
    fi
}

# Neuen Mount erstellen
create_new_mount() {
    read -r -p "Geben Sie den Namen für den neuen Mount ein (ohne .mount): " mount_name
    local mount_file="${MOUNT_FILES_DIR}/${mount_name}.mount"
    if [[ -f "$mount_file" ]]; then
        log "ERROR" "Ein Mount mit diesem Namen existiert bereits."
        return
    fi
    read -r -p "Geben Sie den Quellpfad ein: " source_path
    read -r -p "Geben Sie den Zielpfad ein: " target_path
    read -r -p "Geben Sie den Dateisystemtyp ein (z.B. nfs, cifs): " fs_type
    
    cat > "$mount_file" << EOF
[Unit]
Description=Mount for $mount_name

[Mount]
What=$source_path
Where=$target_path
Type=$fs_type

[Install]
WantedBy=multi-user.target
EOF

    log "INFO" "Neue Mount-Datei erstellt: $mount_file"
}

# Zugangsdaten verwalten
manage_credentials() {
    while true; do
        echo "=== Zugangsdaten verwalten ==="
        local cred_files=(".smb.cred" ".nfs.cred")
        for i in "${!cred_files[@]}"; do
            local cred_file="${HOME}/${cred_files[$i]}"
            if [[ -f "$cred_file" ]]; then
                echo -e "${GREEN}$((i+1))) ${cred_files[$i]}${NC}"
            else
                echo -e "${RED}$((i+1))) ${cred_files[$i]}${NC}"
            fi
        done
        echo "Z) Zurück zum Hauptmenü"
        read -r -p "Wählen Sie eine Option: " choice
        case $choice in
            [1-9]*)
                if ((choice <= ${#cred_files[@]})); then
                    edit_credential_file "${HOME}/${cred_files[$((choice-1))]}"
                else
                    log "WARN" "Ungültige Auswahl."
                fi
                ;;
            Z|z) break ;;
            *) log "WARN" "Ungültige Option." ;;
        esac
    done
}

# Zugangsdatei bearbeiten
edit_credential_file() {
    local cred_file="$1"
    if [[ "$cred_file" != "${HOME}"/* ]]; then
        log "ERROR" "Unerlaubter Zugriff auf Datei außerhalb des Home-Verzeichnisses."
        return
    fi
    if [[ ! -f "$cred_file" ]]; then
        touch "$cred_file"
    fi
    chmod 600 "$cred_file"
    ${EDITOR:-vi} "$cred_file"
    log "INFO" "Zugangsdatei $cred_file bearbeitet."
}

# Konfiguration verwalten
manage_configuration() {
    while true; do
        echo "=== Konfiguration verwalten ==="
        echo "Aktuelle Konfiguration:"
        echo "1) Mount Files Verzeichnis: $MOUNT_FILES_DIR"
        echo "2) Ziel-Mount-Verzeichnis: $MOUNT_TARGET_DIR"
        echo "3) Zurück zum Hauptmenü"
        read -r -p "Wählen Sie eine Option zum Ändern (1-3): " choice
        case $choice in
            1)
                read -r -p "Neues Mount Files Verzeichnis: " new_dir
                if [[ -d "$new_dir" ]]; then
                    MOUNT_FILES_DIR="$new_dir"
                    update_config
                else
                    log "ERROR" "Das angegebene Verzeichnis existiert nicht."
                fi
                ;;
            2)
                read -r -p "Neues Ziel-Mount-Verzeichnis: " new_dir
                if [[ -d "$new_dir" ]]; then
                    MOUNT_TARGET_DIR="$new_dir"
                    update_config
                else
                    log "ERROR" "Das angegebene Verzeichnis existiert nicht."
                fi
                ;;
            3) break ;;
            *) log "WARN" "Ungültige Option." ;;
        esac
    done
}

# Konfiguration aktualisieren
update_config() {
    local config_file="./mount_manager.conf"
    echo "MOUNT_FILES_DIR=\"$MOUNT_FILES_DIR\"" > "$config_file"
    echo "MOUNT_TARGET_DIR=\"$MOUNT_TARGET_DIR\"" >> "$config_file"
    log "INFO" "Konfiguration aktualisiert."
}

# Hauptprogrammschleife
main() {
    check_sudo
    read_config
    
    while true; do
        show_main_menu
        read -r choice
        case $choice in
            1) manage_mounts ;;
            2) manage_credentials ;;
            3) manage_configuration ;;
            4) log "INFO" "Programm wird beendet."; exit 0 ;;
            *) log "WARN" "Ungültige Option. Bitte wählen Sie 1-4." ;;
        esac
    done
}

# Programm starten
main