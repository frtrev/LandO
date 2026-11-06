import 'package:flutter/material.dart';
import '../../models/chat_message.dart';
import '../../services/ai_answer_reporter.dart';
import '../privacy_policy_page.dart';

class ReportAnswerSheet extends StatefulWidget {
  final ChatMessage message;
  final AiAnswerReporter? reporter;
  const ReportAnswerSheet({super.key, required this.message, this.reporter});
  @override
  State<ReportAnswerSheet> createState() => _ReportAnswerSheetState();
}

class _ReportAnswerSheetState extends State<ReportAnswerSheet> {
  final comments = TextEditingController();
  late final reporter = widget.reporter ?? AiAnswerReporter();
  String reason = 'Offensive or unsafe';
  bool includeAnswer = false, busy = false;
  String? error;
  Future<void> send() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await reporter.send(
        reason: reason,
        comments: comments.text,
        answer: includeAnswer
            ? widget.message.text.substring(
                0,
                widget.message.text.length.clamp(0, 12000),
              )
            : null,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Report accepted by the reporting service. Thank you.'),
        ),
      );
    } on ReportException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    comments.dispose();
    reporter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report this answer',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Send feedback to LandO support through FormSubmit. Only the fields below are sent. Your full conversation, property database and API settings are not attached.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final label in [
                    'Offensive or unsafe',
                    'Incorrect or misleading',
                    'Other',
                  ])
                    DropdownMenuItem(value: label, child: Text(label)),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => reason = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comments,
                enabled: !busy,
                minLines: 2,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Comments (optional with an attached answer)',
                  helperText:
                      'Do not include passwords or other private information.',
                  border: OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include this answer'),
                subtitle: const Text(
                  'The answer may contain property details. Only this answer, up to 12,000 characters, is included.',
                ),
                value: includeAnswer,
                onChanged: busy
                    ? null
                    : (value) => setState(() => includeAnswer = value!),
              ),
              if (includeAnswer)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      widget.message.text.substring(
                        0,
                        widget.message.text.length.clamp(0, 12000),
                      ),
                    ),
                  ),
                ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivacyPolicyPage(),
                        ),
                      ),
                child: const Text('Privacy & support'),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy ? null : send,
                    child: Text(busy ? 'Sending…' : 'Send report'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
