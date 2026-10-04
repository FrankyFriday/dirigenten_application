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
    final isDownloading = ref.watch(downloadInProgressProvider);

    return AlertDialog(
      title: const Text('Update verfügbar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update_alt_rounded,
                    size: 18, color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 8),
                Text(
                  'Version ${updateInfo.version}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Änderungen: ${updateInfo.notes}'),
          if (updateInfo.mandatory) ...[
            const SizedBox(height: 14),
            const Text(
              'Dieses Update ist erforderlich.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
          if (isDownloading) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(value: downloadProgress),
            const SizedBox(height: 8),
            Text('Download ${(downloadProgress * 100).toStringAsFixed(0)}%'),
          ],
        ],
      ),
      actions: [
        if (!updateInfo.mandatory && !isDownloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Später'),
          ),
        FilledButton.icon(
          onPressed: isDownloading ? null : () => _startDownload(context, ref),
          icon: Icon(isDownloading
              ? Icons.downloading_rounded
              : Icons.download_rounded),
          label: Text(isDownloading ? 'Lädt …' : 'Herunterladen'),
        ),
      ],
    );
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    if (ref.read(downloadInProgressProvider)) return;

    final downloadingNotifier = ref.read(downloadInProgressProvider.notifier);
    final progressNotifier = ref.read(downloadProgressProvider.notifier);
    downloadingNotifier.state = true;
    final progressController = StreamController<double>();
    final subscription = progressController.stream.listen(
      progressNotifier.updateProgress,
      onError: (Object error, StackTrace stackTrace) {
        UpdateLogger.error(
          'Download-Fortschritt konnte nicht gelesen werden',
          error,
          stackTrace,
        );
      },
    );

    try {
      final updateService = ref.read(updateServiceProvider);

      final filePath = await UpdateService.retry(
        () async {
          final path = await updateService.downloadUpdate(
            updateInfo,
            progressController,
          );
          if (path == null) {
            throw StateError(
              'Update konnte nicht heruntergeladen oder verifiziert werden.',
            );
          }
          return path;
        },
        3,
        const Duration(seconds: 2),
      );

      UpdateLogger.info('Download completed: $filePath');
      if (!context.mounted) return;
      final opened = await _openInstaller(context, filePath);
      if (opened && context.mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      UpdateLogger.error('Download error', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update fehlgeschlagen: $e')));
      }
    } finally {
      await subscription.cancel();
      await progressController.close();
      progressNotifier.reset();
      downloadingNotifier.state = false;
    }
  }

  Future<bool> _openInstaller(BuildContext context, String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        UpdateLogger.warning('Failed to open installer: ${result.message}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Installer konnte nicht geöffnet werden: ${result.message}',
              ),
            ),
          );
        }
        return false;
      } else {
        UpdateLogger.info('Installer opened successfully');
        return true;
      }
    } catch (e) {
      UpdateLogger.error('Error opening installer', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Öffnen des Installers: $e')),
        );
      }
      return false;
    }
  }
}
