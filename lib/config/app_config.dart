/// Zentrale Konfiguration für die Kommunikation mit dem `noten-server` (v2).
///
/// Diese Werte müssen exakt zu dem passen, was der Server erwartet bzw.
/// sendet (siehe `noten-server/README.md` und `bin/server.dart`).
class AppConfig {
  /// App-Kennung, die bei der WebSocket-Registrierung
  /// (`{"type":"register","app":...}`) an den Server geschickt wird und die
  /// der Server auch im `release_announce` (`msg['app']`) verwendet.
  ///
  /// Der Server normalisiert diese ID beim Registrieren und in
  /// `release_announce` auf `dirigenten_app`.
  static const String appId = 'dirigenten_application';
  static const String canonicalServerAppId = 'dirigenten_app';

  static bool matchesServerAppId(Object? value) =>
      value == appId || value == canonicalServerAppId;

  /// Domain des noten-server v2 WebSocket-Endpunkts (`wss://$wsDomain`).
  static const String wsDomain = 'notenserver.mattis-westerhoff.de';
}
