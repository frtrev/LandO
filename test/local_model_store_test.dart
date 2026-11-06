import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lando/services/assistant/local_model_store.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('lando-model-test-'),
  );
  tearDown(() async => root.delete(recursive: true));
  LocalModelStore store(
    List<int> body, {
    List<int>? expected,
    int status = 200,
    void Function()? requested,
  }) => LocalModelStore(
    directory: () async => root,
    clientFactory: () => MockClient((_) async {
      requested?.call();
      return http.Response.bytes(body, status);
    }),
    expectedBytes: (expected ?? body).length,
    expectedDigest: sha256.convert(expected ?? body).toString(),
  );
  test(
    'verified download is reused, survives a new store, and can be removed',
    () async {
      var requests = 0;
      final models = store([1, 2, 3], requested: () => requests++);
      expect(await models.isInstalled(), false);
      expect(await models.download(), true);
      expect(await models.isInstalled(), true);
      expect(await models.download(), true);
      expect(requests, 1);
      final reopened = store([1, 2, 3]);
      expect(await reopened.isInstalled(), true);
      await reopened.remove();
      expect(await models.isInstalled(), false);
    },
  );
  test(
    'same size corrupt weights and partial downloads are never installed',
    () async {
      final models = store([1, 2, 4], expected: [1, 2, 3]);
      expect(await models.download(), false);
      expect(models.error, contains('verification failed'));
      expect(await models.isInstalled(), false);
      expect(
        await File('${(await models.modelFile).path}.part').exists(),
        false,
      );
      final short = store([1, 2], expected: [1, 2, 3]);
      expect(await short.download(), false);
      expect(await short.isInstalled(), false);
    },
  );
  test('HTTP failures leave no installed file and allow retry', () async {
    final models = store([1, 2, 3], status: 503);
    expect(await models.download(), false);
    expect(models.downloading, false);
    expect(await models.isInstalled(), false);
    expect(await store([1, 2, 3]).download(), true);
  });
  test(
    'cancel removes an unfinished model and never marks it installed',
    () async {
      final chunks = StreamController<List<int>>();
      final requested = Completer<void>();
      final models = LocalModelStore(
        directory: () async => root,
        expectedBytes: 3,
        expectedDigest: sha256.convert([1, 2, 3]).toString(),
        clientFactory: () => MockClient.streaming((request, body) async {
          requested.complete();
          return http.StreamedResponse(chunks.stream, 200, contentLength: 3);
        }),
      );
      final download = models.download();
      await requested.future;
      models.cancel();
      chunks.add([1]);
      await chunks.close();
      expect(await download, false);
      expect(models.error, 'Download cancelled.');
      expect(models.downloading, false);
      expect(await models.isInstalled(), false);
      expect(
        await File('${(await models.modelFile).path}.part').exists(),
        false,
      );
    },
  );
}
