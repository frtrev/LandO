import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lando/services/assistant/local_model_store.dart';
import 'package:lando/widgets/assistant/ai_settings_sheet.dart';
import 'support/assistant_fixtures.dart';

class SettingsModels extends LocalModelStore {
  bool ready = false;
  int downloads = 0;
  @override
  Future<bool> isInstalled() async => ready;
  @override
  Future<bool> download() async {
    downloads++;
    ready = true;
    notifyListeners();
    return true;
  }

  @override
  Future<void> remove() async {
    ready = false;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'Qwen offers a download instead of a key and keeps cloud settings',
    (tester) async {
      final models = SettingsModels(),
          repo = ChatMemoryRepository(),
          keys = MemoryKeyStore();
      await keys.save('sk-cloud-retained');
      await repo.setPreference('aiProvider', 'qwen');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiSettingsSheet(
              repository: repo,
              keyStore: keys,
              localModels: models,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Qwen API key'), findsNothing);
      expect(find.text('Download Qwen 3.5'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save AI settings'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Download Qwen 3.5'));
      await tester.tap(find.text('Download Qwen 3.5'));
      await tester.pumpAndSettle();
      expect(models.downloads, 1);
      expect(find.textContaining('Ready for offline chat'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save AI settings'),
            )
            .onPressed,
        isNotNull,
      );
      expect(await keys.read(), 'sk-cloud-retained');
      expect(
        await repo.preference('queryInternet'),
        isNull,
      ); // Default remains enabled until saved.
    },
  );
}
