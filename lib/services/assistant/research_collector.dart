import 'dart:convert';
import '../../models/web_research.dart';

/// Collects search provenance across tool rounds; offsets refer only to the
/// final visible answer. Sources from earlier rounds remain available as links.
class ResearchCollector {
  bool searched = false;
  final List<WebCitation> _citations = [];
  final List<String> _suggestions = [];

  void nextAnswer() {
    for (var i = 0; i < _citations.length; i++) {
      final c = _citations[i];
      _citations[i] = WebCitation(start: 0, end: 0, url: c.url, title: c.title);
    }
  }

  void openAi(List<Map<String, dynamic>> output) {
    nextAnswer();
    var offset = 0;
    for (final item in output) {
      if (item['type'] == 'web_search_call' && item['status'] == 'completed') {
        searched = true;
      }
      if (item['type'] != 'message') continue;
      for (final part in item['content'] as List? ?? []) {
        if (part['type'] != 'output_text' && part['type'] != 'refusal') {
          continue;
        }
        final text = (part['text'] ?? part['refusal'] ?? '') as String;
        for (final annotation in part['annotations'] as List? ?? []) {
          if (annotation['type'] != 'url_citation') continue;
          final citation = WebCitation.parse(annotation as Map, offset: offset);
          if (citation != null && citation.end <= offset + text.length) {
            _citations.add(citation);
            searched = true;
          }
        }
        offset += text.length + 2;
      }
    }
  }

  void gemini(Map<String, dynamic> candidate, String text) {
    nextAnswer();
    final metadata = candidate['groundingMetadata'] as Map?;
    if (metadata == null) return;
    if ((metadata['webSearchQueries'] as List? ?? []).isNotEmpty) {
      searched = true;
    }
    final html = (metadata['searchEntryPoint'] as Map?)?['renderedContent'];
    if (html is String && html.isNotEmpty && !_suggestions.contains(html)) {
      _suggestions.add(html);
    }
    final chunks = metadata['groundingChunks'] as List? ?? [];
    final sources = <int, Map>{};
    for (var i = 0; i < chunks.length; i++) {
      final web = (chunks[i] as Map)['web'] as Map?;
      if (web != null &&
          web['uri'] is String &&
          WebCitation.validUrl(web['uri'] as String)) {
        sources[i] = web;
        searched = true;
        _citations.add(
          WebCitation(
            start: 0,
            end: 0,
            url: web['uri'] as String,
            title:
                (web['title'] ?? Uri.parse(web['uri'] as String).host)
                    as String,
          ),
        );
      }
    }
    // GenerateContent segment offsets are UTF-8 byte offsets, whereas Flutter
    // spans use UTF-16 string offsets. Decode only complete validated prefixes.
    final bytes = utf8.encode(text);
    for (final support in metadata['groundingSupports'] as List? ?? []) {
      final segment = support['segment'] as Map? ?? {};
      final start = segment['startIndex'] ?? 0, end = segment['endIndex'];
      if (start is! int ||
          end is! int ||
          start < 0 ||
          end < start ||
          end > bytes.length) {
        continue;
      }
      int charStart, charEnd;
      try {
        charStart = utf8.decode(bytes.sublist(0, start)).length;
        charEnd = utf8.decode(bytes.sublist(0, end)).length;
      } on FormatException {
        continue;
      }
      for (final index in support['groundingChunkIndices'] as List? ?? []) {
        final web = sources[index];
        if (web == null) continue;
        _citations.add(
          WebCitation(
            start: charStart,
            end: charEnd,
            url: web['uri'] as String,
            title:
                (web['title'] ?? Uri.parse(web['uri'] as String).host)
                    as String,
          ),
        );
      }
    }
  }

  WebResearch? get result => searched
      ? WebResearch(
          checkedAt: DateTime.now().toUtc(),
          citations: List.unmodifiable(_citations),
          searchSuggestions: List.unmodifiable(_suggestions),
        )
      : null;
}
