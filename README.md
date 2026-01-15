# 🎼 Marschpad – Dirigenten Application

Die Marschpad Dirigenten Application ist eine Flutter-basierte Steuerungs-App für Dirigenten von Musikvereinen, Orchestern und Spielmannszügen.
Sie ermöglicht die zentrale Kontrolle von Notenstücken und die Echtzeit-Steuerung aller verbundenen Musiker-Apps.

Die Anwendung ist Teil des Marschpad-Gesamtsystems und arbeitet nahtlos mit der Musiker-App, einem WebSocket-Server sowie einer Nextcloud-Instanz zusammen.
PDF-Dateien werden niemals über den Server übertragen, sondern ausschließlich direkt aus Nextcloud geladen, um Performance, Stabilität und Sicherheit zu gewährleisten.

## ✨ FUNKTIONEN

Anzeige aller verfügbaren Notenstücke aus Nextcloud

Automatische Gruppierung nach Werk, Instrument und Stimme

Starten eines Stücks per Knopfdruck

Beenden eines Stücks mit sofortigem Schließen bei allen Musikern

Echtzeit-Statusanzeige (verbundene Musiker und Dirigenten)

Keine PDF-Übertragung über WebSocket

Extrem geringe Netzlast durch reine JSON-Steuersignale

## 🧩 SYSTEMARCHITEKTUR

Die Dirigenten-App kommuniziert ausschließlich per WebSocket mit dem Server.
Es werden nur Steuerbefehle übertragen – keine PDFs, keine Binärdaten, keine Noten.

Ablauf

Dirigent wählt ein Stück aus

Dirigent sendet ein send_piece_signal

Musiker-Apps laden automatisch ihre passenden PDFs direkt aus Nextcloud

Dirigent beendet das Stück

Musiker-Apps schließen das PDF sofort und synchron

Diese Architektur sorgt für maximale Skalierbarkeit, minimale Latenz und saubere Trennung der Verantwortlichkeiten.

## ☁️ NEXTCLOUD-INTEGRATION

Die Dirigenten-App liest ausschließlich Dateinamen aus Nextcloud, um verfügbare Stücke anzuzeigen.
Ein Download von PDFs findet nicht statt.

Der Zugriff erfolgt über WebDAV mit Zugangsdaten aus einer .env-Datei.

## 📁 DATEINAMEN-KONVENTION

Alle PDF-Dateien müssen nach folgendem Schema benannt sein:

Stück_Instrument_Stimme.pdf

Nur bei Einhaltung dieser Konvention können die Musiker-Apps automatisch die korrekten Noten finden und laden.

## 🛠 TECHNIK

Flutter

Dart

WebSocket (JSON-Steuerdaten)

Nextcloud WebDAV

Material Design

## ▶️ START DER APP

Abhängigkeiten installieren:

flutter pub get


App starten:

flutter run

## ⚠️ WICHTIGE HINWEISE

Die Dirigenten-App lädt keine PDFs

Sie dient ausschließlich der Steuerung

Musiker-Apps sind verantwortlich für Download, Caching und Anzeige

Der WebSocket-Server muss erreichbar sein

Die Nextcloud-Instanz muss korrekt konfiguriert sein

## 🔐 SICHERHEIT

WebSocket-Verbindungen ausschließlich über WSS

Nextcloud-Zugriff über Basic Authentication

Keine sensiblen Zugangsdaten im Quellcode

Konfigurationsdaten ausschließlich über .env

## 📜 LIZENZ

Interne Nutzung – Musikverein Scharrel
Alle Rechte vorbehalten.

## 🎺 ENTWICKELT FÜR DIE PRAXIS

Weniger Papier.
Mehr Übersicht.
Mehr Musik.
