import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'qwen_on_device_test.dart' as qwen;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native iOS address search resolves a known street address', (
    tester,
  ) async {
    expect(Platform.isIOS, true);
    await tester.runAsync(() async {
      const channel = MethodChannel('lando/places');
      final matches = await channel.invokeListMethod<dynamic>('search', {
        'query': '678 Alexandria Dr, Collierville, TN',
      });
      expect(matches, isNotEmpty);
      final first = Map<String, dynamic>.from(matches!.first as Map);
      final result = first.containsKey('placeId')
          ? Map<String, dynamic>.from(
              (await channel.invokeMapMethod<String, dynamic>('resolve', {
                'placeId': first['placeId'],
                'name': first['name'],
              }))!,
            )
          : first;
      expect((result['latitude'] as num).toDouble(), closeTo(35.04, 0.1));
      expect((result['longitude'] as num).toDouble(), closeTo(-89.66, 0.1));
      expect(result['name'].toString().toLowerCase(), contains('alexandria'));
    });
  });
  qwen.main();
}
