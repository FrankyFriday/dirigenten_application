# Marschpad – Dirigenten-App

Die Dirigenten-App ist das Steuerpult für den Musikverein Scharrel. Sie zeigt
die verfügbaren Notenstücke an und sendet Start- und Stoppsignale an die
verbundenen Musikergeräte. Die Oberfläche ist für den Einsatz während der
Probe ausgelegt und unterstützt helle und dunkle Darstellung.

## Funktionen

- Echtzeitverbindung zum Notenserver mit automatischer Wiederverbindung
- Anzeige des Verbindungs- und Wartungsstatus sowie verbundener Geräte
- Suche und Filterung der verfügbaren Stücke
- Starten und synchrones Beenden eines Stücks auf den Musikergeräten
- Empfang von Servermeldungen und App-Release-Hinweisen
- Update-Download mit Prüfung von Paketname, Version und Android-Signatur

## Zusammenspiel der Apps

Die Apps verwenden `wss://ws.notenserver.duckdns.org` für die WebSocket-
Steuerung. Beim Verbinden registriert sich die Dirigenten-App mit der Kennung
`dirigenten_application`; der Server verwendet dafür auch die kanonische
Kennung `dirigenten_app`.

Die Stückliste kommt über `GET /api/notes` vom Notenserver. Die Dirigenten-App
lädt keine PDFs und überträgt keine Notendateien über WebSocket. Für ein Stück
sendet sie ein Steuersignal. Die Musiker-App lädt anschließend die passenden
PDFs über den Notenserver-Proxy. Die Dateinamen müssen dem Schema
`Stück_Instrument_Stimme.pdf` entsprechen, zum Beispiel
`Marsch_Trompete_1.pdf`.

Der Notenserver-Proxy ist derzeit nicht durch eine Anmeldung der Apps
geschützt. Wer den Server erreichen kann, kann daher die dort bereitgestellte
Notenliste und PDFs abrufen. Nextcloud-Zugangsdaten gehören ausschließlich in
die Server- bzw. CI-Konfiguration und niemals in die App.

## Entwickeln und prüfen

Voraussetzungen: Flutter/Dart gemäß `pubspec.yaml` sowie ein Android-SDK für
Android-Builds.

```powershell
flutter pub get
flutter analyze --no-pub lib
flutter test --no-pub
flutter run
```

Die Serveradresse und App-Kennung sind in `lib/config/app_config.dart`
hinterlegt. Änderungen an der Serveradresse müssen mit dem Notenserver und
der Musiker-App abgestimmt werden.

## Android-Release

Der Workflow **Android Release** in GitHub Actions baut ein signiertes APK,
prüft Version und Signatur, lädt das APK zu Nextcloud hoch und erstellt einen
Octopus-Release für `dirigenten_application`. Er kann über einen Tag `vX.Y.Z`
oder manuell mit einer Version im Format `X.Y.Z` gestartet werden.

Im GitHub-Repository müssen die Actions-Secrets `KEYSTORE_BASE64`,
`KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`, `NC_USER`, `NC_PASS`,
`OCTOPUS_API_KEY` und `OCTOPUS_SPACE` vorhanden sein. Der Workflow dekodiert
den Keystore temporär, prüft ihn mit `keytool` und erzeugt daraus die
Signierungskonfiguration. Keystore und Passwörter dürfen weder eingecheckt
noch in Logs ausgegeben werden.

## Projektstruktur

- `lib/pages/conductor_page.dart` – Dirigentenpult und WebSocket-Steuerung
- `lib/services/` – Notenserver, WebSocket, Updates und Benachrichtigungen
- `lib/theme/app_theme.dart` – gemeinsames helles und dunkles Designsystem
- `android/` – Android-App und Release-Signierung
- `.github/workflows/` – Android-Release und gezielte Octopus-Reparatur

## Lizenz

Interne Nutzung – Musikverein Scharrel. Alle Rechte vorbehalten.
