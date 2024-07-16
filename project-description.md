# Linux Mount Manager

## Projektbeschreibung

Der Linux Mount Manager ist ein umfassendes Bash-Skript zur Verwaltung von benutzerdefinierten Mount-Punkten unter Linux. Es bietet eine benutzerfreundliche Schnittstelle zur Erstellung, Bearbeitung, Aktivierung und Deaktivierung von systemd Mount-Units, sowie zur Verwaltung von Zugangsdaten für verschiedene Dateisysteme. Das Skript ist darauf ausgelegt, die Verwaltung von Mounts zu vereinfachen und gleichzeitig Flexibilität und Sicherheit zu gewährleisten.

## Hauptfunktionen

1. **Mount-Verwaltung**
   - Erstellung und Bearbeitung von .mount-Dateien
   - Aktivierung und Deaktivierung von Mount-Punkten
   - Statusanzeige aller verwalteten Mounts
   - Unterstützung für verschiedene Dateisystemtypen (auto, smb, nfs, etc.)

2. **Zugangsdaten-Verwaltung**
   - Erstellung und Bearbeitung von Zugangsdaten für SMB- und NFS-Mounts
   - Sichere Speicherung von Zugangsdaten mit eingeschränkten Berechtigungen

3. **Konfigurationsmanagement**
   - Festlegung und Änderung von Mount-Verzeichnissen
   - Konfiguration von Mount-Optionen und Dateisystemtypen
   - Dynamische Anpassung der Konfiguration während der Laufzeit

4. **Systemintegration**
   - Verwendung von systemd für Mount-Verwaltung
   - Automatische Erstellung und Verwaltung von systemd Mount-Units
   - Integration mit dem Linux-Dateisystem und Berechtigungssystem

5. **Logging und Fehlerbehandlung**
   - Detailliertes Logging aller Aktivitäten in /var/log/custom-mounts.log
   - Farbcodierte Konsolenausgaben für bessere Lesbarkeit
   - Umfassende Fehlerprüfungen und benutzerfreundliche Fehlermeldungen

6. **Benutzerinteraktion**
   - Interaktives Menüsystem für einfache Bedienung
   - Eingabeaufforderungen mit Standardwerten für schnelle Konfiguration
   - Bestätigungsaufforderungen für kritische Aktionen

## Technische Details

- **Skriptsprache**: Bash
- **Abhängigkeiten**: systemd, sudo
- **Konfigurationsdatei**: /etc/custom-mount-manager.conf
- **Mount-Unit Speicherort**: /etc/systemd/system/
- **Log-Datei**: /var/log/custom-mounts.log
- **Unterstützte Dateisystemtypen**: auto, smb, nfs, und andere von systemd unterstützte Typen

## Funktionsweise

1. **Initialisierung**
   - Überprüfung der sudo-Rechte
   - Laden der Konfiguration aus /etc/custom-mount-manager.conf
   - Festlegung der Mount-Verzeichnisse (MOUNT_BASE_DIR und SYSTEMD_MOUNT_FILES_DIR)

2. **Hauptmenü**
   - Benutzerfreundliches Menü zur Auswahl verschiedener Aktionen:
     1. Aktiviere Mounts
     2. Deaktiviere Mounts
     3. Zeige Status
     4. Erstelle/Bearbeite Mount-Datei
     5. Erstelle/Bearbeite Zugangsdaten (SMB/NFS)
     6. Ändere Mount-Konfigurationen
     7. Beenden

3. **Mount-Operationen**
   - Erstellung/Bearbeitung von Mount-Dateien mit benutzerdefinierten Einstellungen (What, Where, Type, Options)
   - Aktivierung von Mounts durch Kopieren der .mount-Dateien nach /etc/systemd/system/ und Aktivierung via systemctl
   - Deaktivierung von Mounts durch Stoppen und Entfernen der systemd-Units
   - Automatische Erstellung von Verzeichnissen für Mount-Punkte

4. **Zugangsdaten-Verwaltung**
   - Erstellung und Bearbeitung von .creds-Dateien für SMB und NFS
   - Sichere Speicherung mit eingeschränkten Berechtigungen (600)
   - Unterschiedliche Handhabung für SMB (username/password) und NFS (options)

5. **Statusüberwachung**
   - Anzeige des aktuellen Status aller verwalteten Mounts (aktiv/inaktiv)
   - Verwendung von systemctl zur Statusabfrage

6. **Fehlerbehandlung und Logging**
   - Umfassende Fehlerprüfungen und benutzerfreundliche Fehlermeldungen
   - Detailliertes Logging aller Aktionen in /var/log/custom-mounts.log
   - Verwendung von Farbcodes für Konsolenausgaben (Rot für Fehler, Grün für Erfolg, Gelb für Warnungen)

7. **Konfigurationsmanagement**
   - Dynamische Änderung von Mount-Verzeichnissen während der Laufzeit
   - Validierung von Verzeichnispfaden mit Option zur automatischen Erstellung

## Sicherheitsaspekte

- Verwendung von sudo für privilegierte Operationen
- Sichere Handhabung von Zugangsdaten mit eingeschränkten Dateiberechtigungen (600)
- Keine Speicherung von Klartext-Passwörtern im Skript
- Überprüfung und Validierung von Benutzereingaben

## Erweiterbarkeit

- Modulare Struktur ermöglicht einfache Erweiterung um zusätzliche Funktionen
- Möglichkeit zur Implementierung von Unterstützung für weitere Dateisystemtypen
- Potenzial für Erweiterung um zusätzliche Netzwerkprotokolle oder Speichertechnologien

## Besondere Funktionen

- Automatische Erkennung und Handhabung von Leerzeichen in Pfadnamen
- Unterstützung für die Verwendung von UUIDs oder Labeln für Geräteidentifikation
- Möglichkeit zur Batch-Verarbeitung mehrerer Mounts gleichzeitig

## Limitationen und bekannte Probleme

- Erfordert root-Rechte oder sudo-Zugriff für die meisten Operationen
- Abhängigkeit von systemd könnte die Kompatibilität mit nicht-systemd-basierten Systemen einschränken
- Keine grafische Benutzeroberfläche, was für einige Benutzer eine Einschränkung darstellen könnte

## Zielgruppe

- Systemadministratoren
- Fortgeschrittene Linux-Benutzer
- IT-Profis, die eine vereinfachte Verwaltung von benutzerdefinierten Mount-Punkten benötigen
- Heimanwender mit komplexen Netzwerkspeicher-Setups

## Voraussetzungen

- Linux-System mit systemd
- sudo-Rechte für den ausführenden Benutzer
- Grundlegende Kenntnisse über Linux-Dateisysteme und Mount-Operationen
- Bash-Shell (Version 4.0 oder höher empfohlen)

## Installation und Erste Schritte

1. Kopieren Sie das Skript in ein Verzeichnis Ihrer Wahl (z.B. /usr/local/bin/)
2. Machen Sie das Skript ausführbar: `chmod +x /pfad/zum/skript/custom-mount-manager.sh`
3. Führen Sie das Skript mit sudo-Rechten aus: `sudo /pfad/zum/skript/custom-mount-manager.sh`
4. Folgen Sie den Anweisungen im Hauptmenü, um Mounts zu konfigurieren und zu verwalten

## Zukünftige Entwicklungen

- Implementierung einer optionalen grafischen Benutzeroberfläche
- Erweiterung der Unterstützung für Cloud-Speicherdienste
- Verbesserung der Fehlerbehandlung und Wiederherstellungsmechanismen
- Integration von Backup- und Snapshot-Funktionen für Mount-Punkte
