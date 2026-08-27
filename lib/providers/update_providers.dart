import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/download_service.dart';
import '../services/update_service.dart';

// Dio provider (nur noch fürs Herunterladen der APK verwendet – der
// frühere Pull-Check gegen eine update.json existiert nicht mehr, siehe
// ConductorPage._handleReleaseAnnounce für den WebSocket-basierten Weg).
final dioProvider = Provider<Dio>((ref) => Dio());

// Download service provider
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final dio = ref.watch(dioProvider);
  return DownloadService(dio);
});

// Update service provider (kümmert sich nur noch ums Herunterladen)
final updateServiceProvider = Provider<UpdateService>((ref) {
  final downloadService = ref.watch(downloadServiceProvider);
  return UpdateService(downloadService);
});

// State for download progress
final downloadProgressProvider = StateNotifierProvider<DownloadProgressNotifier, double>((ref) {
  return DownloadProgressNotifier();
});

class DownloadProgressNotifier extends StateNotifier<double> {
  DownloadProgressNotifier() : super(0.0);

  void updateProgress(double progress) {
    state = progress;
  }

  void reset() {
    state = 0.0;
  }
}
