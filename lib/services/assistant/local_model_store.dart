import 'dart:async';
import 'dart:io';
import 'dart:ffi';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A pinned, hash-verified text-only GGUF. We never execute downloaded code.
class LocalModelStore extends ChangeNotifier {
  static final shared = LocalModelStore();
  bool get supported => !Platform.isAndroid || sizeOf<IntPtr>() == 8;
  static const modelName = 'Qwen 3.5 · 0.8B · Q4_K_M';
  static const fileName = 'Qwen3.5-0.8B-Q4_K_M.gguf';
  static const downloadBytes = 532517120;
  static const digest =
      'bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517';
  static final downloadUri = Uri.parse(
    'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/6ab461498e2023f6e3c1baea90a8f0fe38ab64d0/$fileName',
  );
  final Future<Directory> Function() directory;
  final http.Client Function() clientFactory;
  final Uri uri;
  final int expectedBytes;
  final String expectedDigest;
  LocalModelStore({
    Future<Directory> Function()? directory,
    http.Client Function()? clientFactory,
    Uri? uri,
    this.expectedBytes = downloadBytes,
    this.expectedDigest = digest,
  }) : directory = directory ?? getApplicationSupportDirectory,
       clientFactory = clientFactory ?? http.Client.new,
       uri = uri ?? downloadUri;
  bool downloading = false, verifying = false;
  int received = 0;
  String? error;
  bool _cancelled = false;
  String? _verifiedPath;
  DateTime? _verifiedModified;
  http.Client? _client;
  double get progress => (received / expectedBytes).clamp(0, 1);
  Future<File> get modelFile async =>
      File(p.join((await directory()).path, 'local_models', fileName));
  Future<bool> isInstalled() async {
    if (!supported) return false;
    final file = await modelFile;
    if (!await file.exists()) return false;
    final stat = await file.stat();
    if (stat.size != expectedBytes) return false;
    if (_verifiedPath == file.path && _verifiedModified == stat.modified) {
      return true;
    }
    if ((await sha256.bind(file.openRead()).first).toString() !=
        expectedDigest) {
      return false;
    }
    _verifiedPath = file.path;
    _verifiedModified = stat.modified;
    return true;
  }

  Future<String> installedPath() async {
    if (!await isInstalled()) {
      throw const FormatException(
        'Download the on-device assistant in AI settings first.',
      );
    }
    return (await modelFile).path;
  }

  Future<bool> download() async {
    if (!supported) {
      error =
          'The on-device assistant requires a 64-bit Android installation. Choose a cloud provider on this phone.';
      notifyListeners();
      return false;
    }
    if (downloading) return false;
    downloading = true;
    verifying = false;
    received = 0;
    error = null;
    _cancelled = false;
    notifyListeners();
    File? partial;
    IOSink? sink;
    try {
      if (await isInstalled()) return true;
      final file = await modelFile;
      await file.parent.create(recursive: true);
      // Downloaded weights are recoverable and must not enlarge iCloud backups.
      if (Platform.isIOS) {
        await const MethodChannel(
          'lando/local_models',
        ).invokeMethod<void>('excludeFromBackup', {'path': file.parent.path});
      }
      if (_cancelled) throw const FormatException('Download cancelled.');
      partial = File('${file.path}.part');
      _client = clientFactory();
      final response = await _client!
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const FormatException(
          'Model download unavailable. Please try again later.',
        );
      }
      if (response.contentLength != null &&
          response.contentLength != expectedBytes) {
        throw const FormatException('Unexpected model download size.');
      }
      sink = partial.openWrite();
      var lastUpdate = DateTime.now();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (_cancelled) throw const FormatException('Download cancelled.');
        received += chunk.length;
        if (received > expectedBytes) {
          throw const FormatException('Unexpected model download size.');
        }
        sink.add(chunk);
        // Apply backpressure instead of buffering the entire model in memory.
        await sink.flush();
        if (DateTime.now().difference(lastUpdate).inMilliseconds >= 100) {
          notifyListeners();
          lastUpdate = DateTime.now();
        }
      }
      await sink.close();
      sink = null;
      if (_cancelled) throw const FormatException('Download cancelled.');
      verifying = true;
      notifyListeners();
      if (received != expectedBytes ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              expectedDigest) {
        throw const FormatException(
          'Model verification failed. Please download again.',
        );
      }
      if (_cancelled) throw const FormatException('Download cancelled.');
      await partial.rename(file.path);
      _verifiedPath = file.path;
      _verifiedModified = (await file.stat()).modified;
      return true;
    } on Object catch (e) {
      error = _cancelled
          ? 'Download cancelled.'
          : e is FormatException
          ? e.message
          : 'Download failed. Check your internet connection and available storage, then retry.';
      return false;
    } finally {
      try {
        await sink?.close();
      } on Object {
        /* Preserve the download error. */
      }
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } on Object {
        /* A later download replaces any unfinished file. */
      }
      _client?.close();
      _client = null;
      downloading = false;
      verifying = false;
      notifyListeners();
    }
  }

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  Future<void> remove() async {
    if (downloading) return;
    final file = await modelFile;
    if (await file.exists()) await file.delete();
    _verifiedPath = null;
    _verifiedModified = null;
    error = null;
    notifyListeners();
  }
}
