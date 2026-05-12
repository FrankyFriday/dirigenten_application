# Auto-Update System für Flutter-App

## Übersicht

Dieses professionelle Auto-Update-System ermöglicht der Flutter-App, selbstständig nach neuen Versionen zu suchen, Updates herunterzuladen und zu installieren. Es unterstützt Windows (EXE) und Android (APK) und folgt Clean Architecture Prinzipien.

## Architektur

### Clean Architecture Schichten

1. **Presentation Layer**: UI-Komponenten (UpdateDialog, Progress-Indikatoren)
2. **Domain Layer**: Business Logic (UpdateService, VersionChecker, DownloadService)
3. **Data Layer**: Datenquellen (UpdateRepository)

### State Management

- **Riverpod**: Für Dependency Injection und State Management
- **Streams**: Für Download-Progress-Updates

## Komponenten

### Models
- `UpdateInfo`: DTO für Update-Informationen aus update.json

### Services
- `UpdateService`: Koordiniert Update-Prozesse
- `VersionChecker`: Vergleicht semantische Versionen
- `DownloadService`: Handhabt Downloads mit Progress-Tracking

### Repositories
- `UpdateRepository`: Fetcht Update-Info vom Server

### UI
- `UpdateDialog`: Zeigt Update-Info und Download-Progress

### Utils
- `UpdateLogger`: Logging-System
- `PlatformUtils`: Plattform-spezifische Hilfsfunktionen

## Update Flow

1. **App Start**: SplashScreen checkt für Updates
2. **Fetch update.json**: Repository lädt Update-Info
3. **Version Vergleich**: VersionChecker prüft ob neue Version verfügbar
4. **Update Dialog**: Zeigt Update-Info an
5. **Download**: DownloadService lädt mit Progress-Tracking
6. **Installation**: open_file öffnet Installer

## update.json Format

```json
{
  "version": "1.0.4",
  "mandatory": false,
  "notes": "Bugfixes",
  "url": "https://server/app-1.0.4.exe"
}
```

## Plattform-spezifische Flows

### Windows
- Download: EXE-Datei in Downloads-Ordner
- Installation: open_file startet EXE (Installer übernimmt)

### Android
- Download: APK-Datei in Downloads-Ordner
- Installation: open_file öffnet APK für Installation

## Sicherheit

- **Validierung**: JSON-Schema Validierung für update.json
- **Hash-Verifikation**: (Empfohlen für Produktion) SHA256-Hash-Prüfung
- **HTTPS**: Nur sichere Verbindungen
- **Permissions**: Minimale Berechtigungen

## Fehlerbehandlung

- **Retry-Mechanismus**: Exponential Backoff für Netzwerkfehler
- **Fallback**: Bei Download-Fehlern wird lokaler Fallback verwendet
- **Logging**: Umfassendes Logging für Debugging

## Best Practices

1. **Semantische Versionierung**: Verwende Major.Minor.Patch Format
2. **Mandatory Updates**: Erzwinge kritische Updates
3. **User Experience**: Zeige Progress und erlaube Abbruch
4. **Testing**: Teste alle Flows auf Zielplattformen
5. **Monitoring**: Logge Update-Adoption und Fehler

## Konfiguration

### Provider Setup

```dart
final updateUrlProvider = Provider<String>((ref) => 'https://your-server.com/update.json');
```

### Integration in App

Das System ist in `main.dart` integriert und checkt beim App-Start automatisch für Updates.

## Abhängigkeiten

- `dio`: HTTP-Client für Downloads
- `package_info_plus`: App-Version abrufen
- `path_provider`: Datei-Pfade
- `open_filex`: Dateien öffnen/installieren
- `flutter_riverpod`: State Management
- `version`: Semantische Versionierung

## Erweiterungen

- **Delta Updates**: Nur geänderte Dateien herunterladen
- **Background Updates**: Updates im Hintergrund herunterladen
- **A/B Testing**: Verschiedene Update-Strategien testen
- **Analytics**: Update-Adoption tracken