import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import '../models/update_info.dart';
import '../providers/update_providers.dart';
import '../services/update_service.dart';
import '../utils/logger.dart';

/// Dialog to show update information and allow user to download.
class UpdateDialog extends ConsumerWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadProgress = ref.watch(downloadProgressProvider);
    final isDownloading = downloadProgress > 0 && downloadProgress < 1;

    return AlertDialog(
      title: const Text('Update verfügbar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Neue Version: ${updateInfo.version}'),
          const SizedBox(height: 8),
          Text('Änderungen: ${updateInfo.notes}'),
          if (updateInfo.mandatory) ...[
            const SizedBox(height: 8),
            const Text(
              'Dieses Update ist erforderlich.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
          if (isDownloading) ...[
            const SizedBox(height: 16),
            const Text('Herunterladen...'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: downloadProgress),
            Text('${(downloadProgress * 100).toStringAsFixed(1)}%'),
          ],
        ],
      ),
      actions: [
        if (!updateInfo.mandatory)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Später'),
          ),
        ElevatedButton(
          onPressed: isDownloading ? null : () => _startDownload(context, ref),
          child: Text(isDownloading ? 'Lädt...' : 'Herunterladen'),
        ),
      ],
    );
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    try {
      final updateService = ref.read(updateServiceProvider);
      final progressNotifier = ref.read(downloadProgressProvider.notifier);

      // Create progress stream
      final progressController = StreamController<double>();
      progressController.stream.listen((progress) {
        progressNotifier.updateProgress(progress);
      });

      final filePath = await UpdateService.retry(
        () => updateService.downloadUpdate(updateInfo, progressController),
        3, // max retries
        const Duration(seconds: 2), // initial delay
      );

      if (filePath != null) {
        UpdateLogger.info('Download completed: $filePath');
        // Open the installer
        await _openInstaller(context, filePath);
        // Close dialog and potentially restart app
        if (context.mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download fehlgeschlagen')),
          );
        }
      }
    } catch (e) {
      UpdateLogger.error('Download error', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  Future<void> _openInstaller(BuildContext context, String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        UpdateLogger.warning('Failed to open installer: ${result.message}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Installer konnte nicht geöffnet werden: ${result.message}')),
          );
        }
      } else {
        UpdateLogger.info('Installer opened successfully');
        // On successful open, the app may be closed or restarted by the installer
      }
    } catch (e) {
      UpdateLogger.error('Error opening installer', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Öffnen des Installers: $e')),
        );
      }
    }
  }
}