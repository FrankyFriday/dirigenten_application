/// Zentrale Konfiguration für die Kommunikation mit dem `noten-server` (v2).
///
/// Diese Werte müssen exakt zu dem passen, was der Server erwartet bzw.
/// sendet (siehe `noten-server/README.md` und `bin/server.dart`).
class AppConfig {
  /// App-Kennung, die bei der WebSocket-Registrierung
  /// (`{"type":"register","app":...}`) an den Server geschickt wird und die
  /// der Server auch im `release_announce` (`msg['app']`) verwendet.
  ///
  /// Muss mit dem `app`-Wert übereinstimmen, den z. B. Octopus beim
  /// `POST /api/releases` sendet (siehe Deployment-Fluss im Server-README).
  static const String appId = 'dirigenten_application';

  /// Domain des noten-server v2 WebSocket-Endpunkts (`wss://$wsDomain`).
  static const String wsDomain = 'ws.notenserver.duckdns.org';
}
