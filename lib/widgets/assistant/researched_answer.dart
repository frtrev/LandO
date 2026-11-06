import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../models/chat_message.dart';
import '../../models/answer_excerpt.dart';
import 'calculation_card.dart';
import '../../models/web_research.dart';
import 'report_answer_sheet.dart';

Future<void> openResearchLink(BuildContext context, String url) async {
  if (!WebCitation.validUrl(url)) return;
  try {
    if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      return;
    }
  } on Object {
    // Surface failed platform launches without losing the answer.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open this source. Please try again.'),
      ),
    );
  }
}

/// The normal conversation stays brief; the saved answer remains complete.
class ResearchedAnswer extends StatelessWidget {
  final ChatMessage message;
  const ResearchedAnswer({super.key, required this.message});
  static const shortDisclaimer =
      'AI-generated planning guidance. Verify before acting.';
  static const fullDisclaimer =
      '${WebResearch.disclaimer} Mapped boundaries, dimensions and quantities are planning estimates, not legal surveys. Material requirements depend on the assumptions shown in the calculations. Confirm site conditions, measurements, access, taxes, permits and exclusions with qualified local professionals before committing to work.';

  void showDisclaimer(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Full disclaimer'),
      content: const SingleChildScrollView(child: Text(fullDisclaimer)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  void showDetails(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Answer details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close details',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnswerDetailsContent(message: message),
                  if (message.calculations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Property snapshot · ${message.created.toLocal().toString().split('.').first}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    for (final record in message.calculations)
                      CalculationCard(record: record),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => showDisclaimer(context),
                    child: const Text('Full disclaimer'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (message.role == 'user') return SelectableText(message.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnswerDetailsContent(
          message: message,
          excerpt: AnswerExcerpt.fromText(message.text),
        ),
        const SizedBox(height: 6),
        Text(
          shortDisclaimer,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => showDetails(context),
              child: const Text('View details'),
            ),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => showDisclaimer(context),
              child: const Text('Full disclaimer'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => ReportAnswerSheet(message: message),
              ),
              icon: const Icon(Icons.flag_outlined, size: 16),
              label: const Text('Report answer'),
            ),
          ],
        ),
      ],
    );
  }
}

class AnswerDetailsContent extends StatefulWidget {
  final ChatMessage message;
  final AnswerExcerpt? excerpt;
  const AnswerDetailsContent({super.key, required this.message, this.excerpt});
  @override
  State<AnswerDetailsContent> createState() => _AnswerDetailsContentState();
}

class _AnswerDetailsContentState extends State<AnswerDetailsContent> {
  final List<TapGestureRecognizer> _recognizers = [];
  void clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    clearRecognizers();
    final message = widget.message, research = widget.message.research;
    final excerpt = widget.excerpt;
    final start = excerpt?.start ?? 0,
        endLimit = excerpt?.end ?? message.text.length;
    final suffix = excerpt?.shortened == true ? '…' : '';
    if (research == null) {
      return SelectableText(
        '${message.text.substring(start, endLimit)}$suffix',
      );
    }
    final sources = <String, WebCitation>{};
    for (final citation in research.citations) {
      if (WebCitation.validUrl(citation.url)) {
        sources.putIfAbsent(citation.url, () => citation);
      }
    }
    final urls = sources.keys.toList();
    final at = <int, Set<String>>{};
    for (final citation in research.citations) {
      if (citation.start >= start &&
          citation.end > citation.start &&
          citation.end <= endLimit &&
          sources.containsKey(citation.url)) {
        at.putIfAbsent(citation.end, () => {}).add(citation.url);
      }
    }
    final spans = <InlineSpan>[];
    var cursor = start;
    for (final end in at.keys.toList()..sort()) {
      spans.add(TextSpan(text: message.text.substring(cursor, end)));
      for (final url in at[end]!) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => openResearchLink(context, url);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: ' [${urls.indexOf(url) + 1}]',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          ),
        );
      }
      cursor = end;
    }
    spans.add(
      TextSpan(text: '${message.text.substring(cursor, endLimit)}$suffix'),
    );
    if (excerpt != null) return SelectableText.rich(TextSpan(children: spans));
    final date = research.checkedAt.toLocal().toIso8601String().substring(
      0,
      10,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText.rich(TextSpan(children: spans)),
        const SizedBox(height: 8),
        Text(
          'Internet research · $date',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        if (sources.isEmpty)
          const Text(
            'No source links were returned. This answer could not be independently checked.',
          ),
        for (var i = 0; i < urls.length; i++)
          TextButton.icon(
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(vertical: 4),
            ),
            onPressed: () => openResearchLink(context, urls[i]),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(
              '[${i + 1}] ${sources[urls[i]]!.title}\n${Uri.parse(urls[i]).host}',
            ),
          ),
        for (final html in research.searchSuggestions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SearchSuggestions(html: html),
          ),
        const SizedBox(height: 4),
        Text(
          WebResearch.disclaimer,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Render the search service's attribution HTML without rewriting its content.
/// Destination links open directly in the browser, with no click tracking.
class SearchSuggestions extends StatefulWidget {
  final String html;
  const SearchSuggestions({super.key, required this.html});
  @override
  State<SearchSuggestions> createState() => _SearchSuggestionsState();
}

class _SearchSuggestionsState extends State<SearchSuggestions> {
  late final WebViewController controller;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (WebCitation.validUrl(request.url)) {
              openResearchLink(context, request.url);
              return NavigationDecision.prevent;
            }
            return request.url == 'about:blank' ||
                    request.url.startsWith('data:text/html')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(
        '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body>${widget.html}</body></html>',
      );
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 160, child: WebViewWidget(controller: controller));
}
