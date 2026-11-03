import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lando/models/answer_excerpt.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/widgets/assistant/researched_answer.dart';

void main() {
  test(
    'conversational lead uses original offsets and preserves the full answer',
    () {
      const text =
          'Budget roughly \$1,200–\$2,250 for 150 ft, before extras.\n\nDetails:\nBased on local installed pricing.\nDownspouts and access can change the cost.';
      final excerpt = AnswerExcerpt.fromText(text);
      expect(
        text.substring(excerpt.start, excerpt.end),
        'Budget roughly \$1,200–\$2,250 for 150 ft, before extras.',
      );
      expect(excerpt.shortened, false);
      final message = ChatMessage(role: 'assistant', text: text);
      expect(ChatMessage.fromJson(message.toJson()).text, text);
    },
  );
  test(
    'legacy headings and greetings do not hide the first useful paragraph',
    () {
      const text =
          'Hello! I am LandO.\n\n### Installed pricing\n\nTypical installed pricing is \$8 to \$15 per foot.\n\nThe full explanation remains available.';
      final excerpt = AnswerExcerpt.fromText(text);
      expect(
        text.substring(excerpt.start, excerpt.end),
        'Typical installed pricing is \$8 to \$15 per foot.',
      );
      expect(excerpt.shortened, true);
      final longText = List.filled(
        200,
        'Published pricing varies by location',
      ).join(' ');
      final long = AnswerExcerpt.fromText(longText);
      expect(long.end - long.start, lessThanOrEqualTo(420));
      expect(long.shortened, true);
      for (final value in ['', 'Hello!', 'Which material would you like?']) {
        final short = AnswerExcerpt.fromText(value);
        expect(value.substring(short.start, short.end), value);
      }
    },
  );
  testWidgets(
    'details show the complete saved answer and closing preserves the chat draft',
    (tester) async {
      const complete =
          'Around \$8–\$15 per foot is a useful planning range.\n\nDetails:\nDetailed exclusions: downspouts, removal and fascia repairs.';
      final draft = TextEditingController(text: 'What about copper?');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ResearchedAnswer(
                  message: ChatMessage(role: 'assistant', text: complete),
                ),
                TextField(controller: draft),
              ],
            ),
          ),
        ),
      );
      expect(find.text(complete), findsNothing);
      expect(
        find.text('Around \$8–\$15 per foot is a useful planning range.'),
        findsOneWidget,
      );
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      expect(find.text(complete), findsOneWidget);
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
      expect(find.text(complete), findsNothing);
      expect(draft.text, 'What about copper?');
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    },
  );
}
