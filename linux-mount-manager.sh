#!/usr/bin/env bash

set -euo pipefail

# Linux Mount Manager
# Dieses Skript ermöglicht das Erstellen und Verwalten von Mount-Dateien für Systemd.
# Es kann verwendet werden, um Netzwerkfreigaben (SMB, NFS) oder andere Dateisysteme zu mounten.
# Die Mount-Dateien werden im aktuellen Verzeichnis gespeichert und von dort in /etc/systemd/system kopiert.
# Das Skript kann auch verwendet werden, um Zugangsdaten für SMB- oder NFS-Freigaben zu speichern.
# Die Zugangsdaten-Dateien werden ebenfalls im aktuellen Verzeichnis gespeichert.
# Das Skript kann auch verwendet werden, um die Mounts zu aktivieren/deaktivieren und den Status anzuzeigen.
# Das Skript speichert das Basis-Verzeichnis für die Mount-Punkte in einer Konfigurationsdatei.
# Standardmäßig wird das Basis-Verzeichnis auf /custom-mounts gesetzt.
# Die Konfigurationsdatei kann geändert werden, um das Basis-Verzeichnis zu ändern.
# Das Skript erstellt auch eine Log-Datei in /var/log/custom-mounts.log.
# Das Skript muss mit sudo-Rechten ausgeführt werden.

# Autor: ben7sys


# Konfiguration
readonly SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
readonly CONFIG_FILE="$SCRIPT_DIR/linux-mount-manager.conf"
readonly LOG_FILE="/var/log/custom-mounts.log"
readonly DEFAULT_MOUNT_DESTINATION="/custom-mounts"

# Globale Variablen
MOUNT_BASE_DEST_DIR=""
SYSTEMD_MOUNT_FILES_DIR=""

# Farben für die Ausgabe
declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[1;33m'
    [BLUE]='\033[0;34m'
    [NC]='\033[0m' # No Color
)

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

read_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        MOUNT_BASE_DEST_DIR="$DEFAULT_MOUNT_DESTINATION"
    fi
}

write_config() {
    echo "MOUNT_BASE_DEST_DIR=\"$MOUNT_BASE_DEST_DIR\"" > "$CONFIG_FILE"
}

get_user_input() {
    local prompt="$1"
    local default="$2"
    local options="$3"
    local input

    if [[ -n "$options" ]]; then
        echo "$prompt"
        IFS=',' read -ra ADDR <<< "$options"
        for i in "${!ADDR[@]}"; do
            echo "$((i+1)): ${ADDR[i]}"
        done
        read -rp "Wähle eine Option (1-${#ADDR[@]}): " input
        if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le "${#ADDR[@]}" ]; then
            echo "${ADDR[$((input-1))]}"
        else
            echo "$default"
        fi
    else
        read -rp "$prompt [$default]: " input
        echo "${input:-$default}"
    fi
}

# Das Mount-Ziel-Verzeichnis ist das Ziel-Verzeichnis, an dem die Ziele gemountet werden und wird standardmäßig unter /custom-mounts erstellt.
# Das Verzeichnis wird für die Mount-Punkte wird validiert und ggf. erstellt.
validate_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        local create_dir
        create_dir=$(get_user_input "Das Mount-Ziel-Verzeichnis $dir existiert nicht. Soll es erstellt werden?" "1" "1=Ja,2=Nein")
        if [[ "$create_dir" == "1" ]]; then
            sudo mkdir -p "$dir" || error "Konnte Mount-Ziel-Verzeichnis $dir nicht erstellen."
            print_color "GREEN" "Mount-Ziel-Verzeichnis $dir wurde erstellt."
        else
            error "Das Mount-Ziel-Verzeichnis $dir existiert nicht und wurde nicht erstellt."
        fi
    fi
}

# Die Verzeichnisse für die Mount-Dateien und das Mount-Ziel-Verzeichnis können geändert werden.
get_mount_directories() {
    read_config
    SYSTEMD_MOUNT_FILES_DIR="$SCRIPT_DIR"
    print_color "YELLOW" "Das aktuelle Verzeichnis für Mount-Dateien ist: $SYSTEMD_MOUNT_FILES_DIR"
    
    print_color "YELLOW" "Das aktuelle Mount-Ziel-Verzeichnisfür die Mount-Punkte ist: $MOUNT_BASE_DEST_DIR"
    local change_base_dir
    change_base_dir=$(get_user_input "Möchtest du das Mount-Ziel-Verzeichnis ändern?" "Nein" "Ja,Nein")
    if [[ "$change_base_dir" == "Ja" ]]; then
        MOUNT_BASE_DEST_DIR=$(get_user_input "Gib das neue Mount-Ziel-Verzeichnis für die Mount-Punkte an" "$MOUNT_BASE_DEST_DIR")
        validate_directory "$MOUNT_BASE_DEST_DIR"
        write_config
        print_color "GREEN" "Neues Mount-Ziel-Verzeichnis gespeichert: $MOUNT_BASE_DEST_DIR"
    fi
}

# Erstellt oder bearbeitet Mount-Dateien für Systemd.
create_edit_mount_file() {
    local action
    action=$(get_user_input "Möchtest du eine neue Mount-Datei erstellen oder eine bestehende bearbeiten?" "Neu" "1=Neu,2=Bearbeiten")
    local mount_file

    if [[ "$action" == "Bearbeiten" ]]; then
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

    if [[ "$action" == "Bearbeiten" && -f "$mount_file" ]]; then
        what=$(grep "What=" "$mount_file" | cut -d'=' -f2)
        where=$(grep "Where=" "$mount_file" | cut -d'=' -f2)
        type=$(grep "Type=" "$mount_file" | cut -d'=' -f2)
        options=$(grep "Options=" "$mount_file" | cut -d'=' -f2)
    fi

    what=$(get_user_input "Gib die Quelle ein (What)" "${what:-}")
    where=$(get_user_input "Gib das Ziel ein (Where)" "${where:-$MOUNT_BASE_DEST_DIR/$(basename "$what")}")
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

# Erstellt oder bearbeitet Zugangsdaten-Dateien für SMB oder NFS.
create_edit_credentials() {
    local type="$1"
    local action
    action=$(get_user_input "Möchtest du neue Zugangsdaten erstellen oder bestehende bearbeiten?" "1=Neu,2=Bearbeiten")
    local cred_file

    if [[ "$action" == "2" ]]; then
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
        if [[ "$action" == "2" && -f "$cred_file" ]]; then
            username=$(grep "username=" "$cred_file" | cut -d'=' -f2)
            password=$(grep "password=" "$cred_file" | cut -d'=' -f2)
            print_color "YELLOW" "Aktuelle Zugangsdaten:"
            echo "Benutzername: $username"
            echo "Passwort: ********"
        fi
        username=$(get_user_input "Gib den Benutzernamen ein" "${username:-}")
        password=$(get_user_input "Gib das Passwort ein" "${password:-}")
        echo "username=$username" > "$cred_file"
        echo "password=$password" >> "$cred_file"
    elif [[ "$type" == "nfs" ]]; then
        local options
        if [[ "$action" == "2" && -f "$cred_file" ]]; then
            options=$(cat "$cred_file")
            print_color "YELLOW" "Aktuelle NFS-Optionen:"
            echo "$options"
        fi
        options=$(get_user_input "Gib die NFS-Optionen ein" "${options:-}")
        echo "$options" > "$cred_file"
    fi

    chmod 600 "$cred_file"
    print_color "GREEN" "Zugangsdaten-Datei ${cred_file} wurde erstellt/aktualisiert."
}

# Überprüft, aktiviert und startet einen Mount.
# In summary, this function checks the validity of a mount file, creates the mount path directory, 
# copies the mount file to the appropriate location, enables the mount point if it is not already enabled, 
# and starts the mount point. 
# It provides feedback to the user through colored messages and logs the actions performed.
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

# Entfernt und deaktiviert einen Mount.
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

# Zeigt den Status aller Custom Mounts an.
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

# Aktiviert oder deaktiviert einzelne Mounts.
select_mount() {
    local action="$1"
    local mount_file
    print_color "YELLOW" "Verfügbare Mount-Dateien:"
    select mount_file in "$SYSTEMD_MOUNT_FILES_DIR"/*.mount "Alle" "Zurück"; do
        if [[ "$mount_file" == "Alle" ]]; then
            if [[ "$action" == "activate" ]]; then
                activate_mounts "all"
            elif [[ "$action" == "deactivate" ]]; then
                deactivate_mounts "all"
            fi
            break
        elif [[ "$mount_file" == "Zurück" ]]; then
            return 1
        elif [[ -n "$mount_file" ]]; then
            if [[ "$action" == "activate" ]]; then
                activate_mounts "$mount_file"
            elif [[ "$action" == "deactivate" ]]; then
                deactivate_mounts "$mount_file"
            fi
            break
        else
            print_color "RED" "Ungültige Auswahl. Bitte versuche es erneut."
        fi
    done
}

activate_mounts() {
    local mount_file="$1"
    sudo systemctl daemon-reload
    if [[ "$mount_file" == "all" ]]; then
        while IFS= read -r -d '' mount_file; do
            check_and_enable_mount "$mount_file"
        done < <(find "$SYSTEMD_MOUNT_FILES_DIR" -maxdepth 1 -type f -name "*.mount" -print0)
    else
        check_and_enable_mount "$mount_file"
    fi
}

deactivate_mounts() {
    local mount_file="$1"
    if [[ "$mount_file" == "all" ]]; then
        while IFS= read -r -d '' mount_file; do
            disable_and_remove_mount "$mount_file"
        done < <(find "$SYSTEMD_MOUNT_FILES_DIR" -maxdepth 1 -type f -name "*.mount" -print0)
    else
        disable_and_remove_mount "$mount_file"
    fi
    sudo systemctl daemon-reload
}

main_menu() {
    while true; do
        echo
        print_color "BLUE" "Custom Mount Manager"
        echo "1. Aktiviere Mount(s)"
        echo "2. Deaktiviere Mount(s)"
        echo "3. Zeige Status"
        echo "4. Erstelle/Bearbeite Mount-Datei"
        echo "5. Erstelle/Bearbeite Zugangsdaten (SMB/NFS)"
        echo "6. Ändere Mount-Konfigurationen"
        echo "7. Beenden"
        local option
        option=$(get_user_input "Wähle eine Option" "" "1,2,3,4,5,6,7")
        
        case $option in
            1)
                select_mount "activate"
                ;;
            2)
                select_mount "deactivate"
                ;;
            3)
                show_status
                ;;
            4)
                create_edit_mount_file
                ;;
            5)
                local cred_type
                cred_type=$(get_user_input "Für welchen Typ möchtest du Zugangsdaten erstellen/bearbeiten?" "smb" "smb,nfs")
                create_edit_credentials "$cred_type"
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

# Initialisierung
check_sudo
read_config
get_mount_directories
main_menu
