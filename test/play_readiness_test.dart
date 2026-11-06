import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/services/ai_answer_reporter.dart';
import 'package:lando/services/assistant/assistant_provider.dart';
import 'package:lando/services/assistant/assistant_instructions.dart';
import 'package:lando/widgets/assistant/assistant_sharing_consent.dart';
import 'package:lando/widgets/assistant/property_chat_sheet.dart';
import 'package:lando/widgets/assistant/report_answer_sheet.dart';
import 'package:lando/widgets/privacy_policy_page.dart';
import 'support/assistant_fixtures.dart';
import 'property_chat_controller_test.dart' show FakeAssistant;
import 'package:lando/services/assistant/lando_assistant.dart';

void main() {
  test(
    'report only sends opted-in fields and redacts obvious pasted credentials',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final service = AiAnswerReporter(
        client: MockClient((request) async {
          expect(request.url.scheme, 'https');
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"success":"true","message":"Success"}', 200);
        }),
      );
      await service.send(
        reason: 'Incorrect or misleading',
        comments: 'Wrong unit',
      );
      expect(bodies.single.containsKey('selected_answer'), false);
      expect(bodies.single.keys, isNot(contains('apiKey')));
      await service.send(
        reason: 'Other',
        comments: 'sk-abcdefghijklmnopqrstuv',
        answer: 'Selected answer only',
      );
      expect(bodies.last['comments'], '[credential removed]');
      expect(bodies.last['selected_answer'], 'Selected answer only');
      service.dispose();
    },
  );
  for (final response in [
    http.Response('unavailable', 522),
    http.Response('{"success":"false"}', 200),
    http.Response(
      '{"success":"true","message":"Please activate your form"}',
      200,
    ),
  ]) {
    test(
      'unavailable/rejected/unactivated reports never claim delivery: ${response.body}',
      () async {
        final service = AiAnswerReporter(
          client: MockClient((_) async => response),
        );
        await expectLater(
          service.send(reason: 'Other', comments: 'Please review this answer.'),
          throwsA(isA<ReportException>()),
        );
        service.dispose();
      },
    );
  }
  testWidgets(
    'declining cloud sharing keeps draft and sends nothing; agreeing enables the request',
    (tester) async {
      var calls = 0;
      final repo = ChatMemoryRepository(), property = exampleProperty();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PropertyChatSheet(
              currentProperty: () => property,
              repository: repo,
              keyStore: MemoryKeyStore('sk-test'),
              createAssistant: () => FakeAssistant((p, h) async {
                calls++;
                return const AssistantReply(
                  'Your property has saved measurements.',
                  [],
                );
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'How many acres?');
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(find.text('Allow assistant data sharing?'), findsOneWidget);
      expect(
        find.textContaining('with OpenAI, a third-party AI service'),
        findsOneWidget,
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'How many acres?',
      );
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree & send'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        await repo.preference(
          AssistantSharingConsent.key(AssistantProvider.openai, true),
        ),
        'true',
      );
    },
  );
  testWidgets(
    'offline local requests need no sharing permission; policy is readable without network',
    (tester) async {
      final repo = ChatMemoryRepository();
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const Scaffold();
            },
          ),
        ),
      );
      expect(
        await AssistantSharingConsent.request(
          context,
          repo,
          AssistantProvider.qwen,
          false,
        ),
        true,
      );
      await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('LandO Privacy Policy'), findsOneWidget);
      expect(find.textContaining('ftrevino@yahoo.com'), findsWidgets);
    },
  );
  testWidgets(
    'report form is in-app, opt-in answer unchecked, and failed send preserves comments',
    (tester) async {
      final reporter = AiAnswerReporter(
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportAnswerSheet(
              message: ChatMessage(role: 'assistant', text: 'A saved answer'),
              reporter: reporter,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await tester.enterText(find.byType(TextField), 'Please review this.');
      await tester.ensureVisible(find.text('Send report'));
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Report was not confirmed'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Please review this.',
      );
    },
  );
  test('all cloud prompts include the safety scope', () {
    expect(instructionsForSearch(true), contains(assistantSafetyInstructions));
    expect(instructionsForSearch(false), contains(assistantSafetyInstructions));
  });
  testWidgets('iOS legal notices use bundled native SDK text', (tester) async {
    const channel = MethodChannel('lando/config');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'legalNotices');
          return 'Google Maps\nSDK notices\nGoogle Places\nSDK notices';
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(const MaterialApp(home: MapsLegalNoticesPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Google Places\nSDK notices'), findsOneWidget);
  });
}
