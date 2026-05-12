/// Data Transfer Object for update information fetched from the server.
/// Represents the structure of the update.json file.
class UpdateInfo {
  final String version;
  final bool mandatory;
  final String notes;
  final String url;

  UpdateInfo({
    required this.version,
    required this.mandatory,
    required this.notes,
    required this.url,
  });

  /// Factory constructor to create UpdateInfo from JSON.
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String,
      mandatory: json['mandatory'] as bool,
      notes: json['notes'] as String,
      url: json['url'] as String,
    );
  }

  /// Converts UpdateInfo to JSON for serialization if needed.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'mandatory': mandatory,
      'notes': notes,
      'url': url,
    };
  }

  @override
  String toString() {
    return 'UpdateInfo(version: $version, mandatory: $mandatory, notes: $notes, url: $url)';
  }
}