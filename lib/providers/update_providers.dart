import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/update_repository.dart';
import '../services/download_service.dart';
import '../services/update_service.dart';
import '../models/update_info.dart';

// Dio provider
final dioProvider = Provider<Dio>((ref) => Dio());

// Update URL provider (configure this with your server URL)
final updateUrlProvider = Provider<String>((ref) => 'https://your-server.com/update.json');

// Repository provider
final updateRepositoryProvider = Provider<UpdateRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final url = ref.watch(updateUrlProvider);
  return UpdateRepository(dio, updateUrl: url);
});

// Download service provider
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final dio = ref.watch(dioProvider);
  return DownloadService(dio);
});

// Update service provider
final updateServiceProvider = Provider<UpdateService>((ref) {
  final repository = ref.watch(updateRepositoryProvider);
  final downloadService = ref.watch(downloadServiceProvider);
  return UpdateService(repository, downloadService);
});

// State for update checking
final updateCheckProvider = StateNotifierProvider<UpdateCheckNotifier, AsyncValue<UpdateInfo?>>((ref) {
  final updateService = ref.watch(updateServiceProvider);
  return UpdateCheckNotifier(updateService);
});

class UpdateCheckNotifier extends StateNotifier<AsyncValue<UpdateInfo?>> {
  final UpdateService _updateService;

  UpdateCheckNotifier(this._updateService) : super(const AsyncValue.loading());

  Future<void> checkForUpdate() async {
    state = const AsyncValue.loading();
    try {
      final updateInfo = await _updateService.checkForUpdate();
      state = AsyncValue.data(updateInfo);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

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