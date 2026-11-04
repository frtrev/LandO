import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/data_backup.dart';
import '../services/property_repository.dart';

class BackupFiles {
  Future<Uint8List?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    final length = await file.length();
    if (length == null || length > DataBackup.maxBytes) {
      throw const FormatException(
        'Cannot read this file, or it exceeds 50 MB.',
      );
    }
    return file.readAsBytes();
  }

  Future<bool> save(DataBackup backup) async =>
      await FilePicker.saveFile(
        fileName: backup.fileName,
        bytes: backup.encode(),
        mimeType: 'application/json',
      ) !=
      null;
  Future<void> share(DataBackup backup, Rect origin) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(backup.encode(), mimeType: 'application/json')],
        fileNameOverrides: [backup.fileName],
        title: 'LandO backup',
        sharePositionOrigin: origin,
      ),
    );
  }
}

class DataTransferSheet extends StatefulWidget {
  final PropertyRepository repository;
  final BackupFiles? files;
  const DataTransferSheet({super.key, required this.repository, this.files});
  @override
  State<DataTransferSheet> createState() => _DataTransferSheetState();
}

class _DataTransferSheetState extends State<DataTransferSheet> {
  late final files = widget.files ?? BackupFiles();
  bool busy = false;
  String? status;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => status = e is FormatException
              ? e.message
              : 'Could not complete the transfer. Your existing data has been kept. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> import() async {
    final bytes = await files.pick();
    if (bytes == null || !mounted) return;
    final backup = DataBackup.decode(bytes);
    final current = await widget.repository.list();
    if (!mounted) return;
    final date = backup.created.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final created =
        '${localizations.formatMediumDate(date)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: SingleChildScrollView(
          child: Text(
            'Created $created\n\n'
            '${backup.properties.length} properties\n${backup.areaCount} areas · ${backup.measurementCount} measurements\n'
            '${backup.conversationCount} conversations${backup.hasDraft ? '\nIncludes an unsaved recovery draft' : ''}\n\n'
            'This replaces all current app data, including ${current.length} saved properties, chats, and preferences. Export a backup first if you want to keep them.\n\n'
            'API keys stay on this device and are not restored from the backup.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace & restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await backup.restore(widget.repository);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Backup & restore',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Keep a complete copy of your properties, areas, measurements, chats, settings, and recovery draft. Restore it after reinstalling or on another phone.',
              ),
              const SizedBox(height: 8),
              const Text(
                'API keys are not included. On a new phone, enter them again in assistant settings. Save outside LandO, such as iCloud Drive or Google Drive, to keep your backup after uninstalling.',
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Save backup to Files'),
                onTap: busy
                    ? null
                    : () => run(() async {
                        final saved = await files.save(
                          await DataBackup.capture(widget.repository),
                        );
                        if (saved && mounted) {
                          setState(() => status = 'Backup saved.');
                        }
                      }),
              ),
              Builder(
                builder: (buttonContext) => ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Share or open backup in another app'),
                  onTap: busy
                      ? null
                      : () {
                          final box =
                              buttonContext.findRenderObject()! as RenderBox;
                          final origin =
                              box.localToGlobal(Offset.zero) & box.size;
                          run(
                            () async => files.share(
                              await DataBackup.capture(widget.repository),
                              origin,
                            ),
                          );
                        },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Import backup file'),
                subtitle: const Text('Choose a LandO .json backup to restore'),
                onTap: busy ? null : () => run(import),
              ),
              if (busy) const LinearProgressIndicator(),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: Text(status!)),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
}
