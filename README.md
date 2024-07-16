# Linux Mount Manager

## Projektbeschreibung

Der Linux Mount Manager ist ein umfassendes Bash-Skript zur Verwaltung von benutzerdefinierten Mount-Punkten unter Linux. Es bietet eine benutzerfreundliche Schnittstelle zur Erstellung, Bearbeitung, Aktivierung und Deaktivierung von systemd Mount-Units, sowie zur Verwaltung von Zugangsdaten. Das Skript ist darauf ausgelegt, die Verwaltung von Mounts zu vereinfachen und gleichzeitig Flexibilität und Sicherheit zu gewährleisten.

# Anforderungen

1. Verwaltung von systemd Mount-Units
   - Erstellen, Bearbeiten, Aktivieren und Deaktivieren von .mount-Dateien
   - Unterstützung für einzelne und Batch-Operationen
   - Option 1: Es können einzelne Mounts aktiviert/deaktivert werden
   - Option 2: Es können alle Mounts aktiviert/deaktiviert

2. Konfigurationsmanagement
   - Lesen/Schreiben einer .conf-Datei im gleichen Verzeichnis wie das Hauptskript
   - Benutzerdefinierbares Mount-Ziel-Verzeichnis mit Persistenz

3. Benutzerinteraktion
   - Menügesteuertes CLI mit numerischer Auswahl
   - Eingabeaufforderungen mit beschrifteten Standardwerten zum Beispiel: 1=Ja, 2=Nein

4. Zugangsdatenverwaltung
   - Erstellen und Bearbeiten von Dateien für SMB- und NFS-Zugangsdaten
   - Sichere Speicherung (chmod 600)
   - Dateinamenformat: .smb.cred .nfs.cred
   - Speicherort im Userhome

5. Verzeichnishandling
   - Validierung und automatische Erstellung von Verzeichnissen

6. Logging und Fehlerbehandlung
   - Detailliertes Logging in /var/log/custom-mounts.log
   - Farbcodierte Konsolenausgaben

7. Sicherheit
   - Überprüfung der sudo-Rechte
   - Sichere Handhabung von Zugangsdaten

8. Flexibilität
   - Unterstützung Dateisystemtypen (smb, nfs)

9. Systemintegration
   - Nutzung von systemd für Mount-Verwaltung
   - Kompatibilität mit bestehenden Linux-Dateisystemen

10. Benutzerfreundlichkeit
    - Klare Menüführung und Statusanzeigen
    - Konsistente Benutzeroberfläche für alle Operationen


## Hauptfunktionen

1. **Mount-Verwaltung**
   - Erstellung und Bearbeitung von .mount-Dateien
   - Aktivierung und Deaktivierung von Mount-Punkten
   - Statusanzeige aller verwalteten Mounts
   - Unterstützung für smb und nfs

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
- **Konfigurationsdatei**: ./custom-mount-manager.conf
- **Mount-Unit Speicherort**: /etc/systemd/system/
- **Log-Datei**: /var/log/linux-mount-manager.log
- **Unterstützte Dateisystemtypen**: smb, nfs

## Funktionsweise

1. **Initialisierung**
   - Überprüfung der sudo-Rechte
   - Laden der Konfiguration aus ./custom-mount-manager.conf
   - Festlegung Verzeichnis für mount-dateien in der Konfiguration anpassbar, persistent 
   - Speicherort der ".cred"-Files
   - Mount-Ziel-Pfad steht in den Mount Dateien.
   - Fehler ausgeben wenn in den Mount Dateien ein Standardpfad gefunden wird. 
        - Ausgeschlossene Standardpfade für Mount-Ziele: /home /mnt /mount /media /var /dev
   
   - Wenn keine Mount-Dateien gefunden werden:
        - Option 1: Pfad zu den Mount-Files angeben
        - Option 2: Mount-File erstellen

2. **Hauptmenü**
   - Benutzerfreundliches Menü zur Auswahl (Verweis auf #Menüführung)

3. **Mount-Operationen**
   - Erstellung/Bearbeitung von Mount-Dateien mit benutzerdefinierten Einstellungen (What, Where, Type, Options)
   - Aktivierung von Mounts durch Kopieren der .mount-Dateien nach /etc/systemd/system/ und Aktivierung via systemctl
   - Deaktivierung von Mounts durch Stoppen und Entfernen der .mount-Dateien von systemd
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

1. Klonen Sie das Projekt oder speichern Sie sich die .conf und .sh datei in einem Verzeichnis Ihrer Wahl
2. Machen Sie das Skript ausführbar: `chmod +x /pfad/zum/skript/custom-mount-manager.sh`
3. Führen Sie das Skript mit sudo-Rechten aus: `sudo /pfad/zum/skript/custom-mount-manager.sh`
4. Folgen Sie den Anweisungen im Hauptmenü, um Mounts zu konfigurieren und zu verwalten

## Zukünftige Entwicklungen

- Implementierung einer optionalen grafischen Benutzeroberfläche
- Erweiterung der Unterstützung für weitere Speicherdienste
- Verbesserung der Fehlerbehandlung


# Menüführung

## Hauptmenü
    1) Mounts verwalten
    2) Zugangsdaten verwalten
    3) Konfiguration verwalten
    0) Beenden

### Submenü "Mounts verwalten"
    1) mount1.mount
    2) mount2.mount
    3) mount3.mount
    4) Alle aktivieren
    5) Alle deaktivieren
    0) Hauptmenu

- Submenü zeigt Liste der Mountfiles und deren Status.
- Wurde eine Auswahl getroffen, wird das mount abhängig vom Status, aktiviert oder deaktiviert.
- Ein aktiviertes mount ist grün.
- Ein deaktiviertes mount ist rot.

### Submenü "Zugangsdaten verwalten"
    1) .smb.cred
    2) .nfs.cred
    0) Hauptmenu

- Liste der Zugangsfiles die in den mount Dateien geschrieben sind, werden hier gelistet.
- Mount-Datei beinhaltet den Pfad zum ".cred"-File
- Wenn ein ".cred"-File nicht existiert ist es rot.
- Wenn ein ".cred"-File existiert ist es grün.

### Submenü 3) Konfiguration verwalten
Die Konfigurationsdatei wird ausgelesen
Der Ort der Mount files kann geändert werden
Der des Ziel-Mount-Verzeichnis kann geändert werden