import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import '../../models/web_research.dart';

class LocalSearchResult {
  final String title, url, snippet;
  const LocalSearchResult(this.title, this.url, this.snippet);
}

/// Public HTML search, with no paid search key or server operated by LandO.
/// Challenges and rate limits are failures, never bypassed or treated as data.
class LocalWebSearch {
  final http.Client client;
  LocalWebSearch({http.Client? client}) : client = client ?? http.Client();
  Future<List<LocalSearchResult>> search(String query) async {
    final response = await client
        .send(
          http.Request(
            'GET',
            Uri.https('html.duckduckgo.com', '/html/', {
              'q': query.substring(0, query.length.clamp(0, 300)),
            }),
          )..headers['User-Agent'] = 'LandO/1.0 (local assistant web search)',
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const FormatException('Search unavailable.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      if (bytes.length + chunk.length > 1000000) {
        throw const FormatException('Search response too large.');
      }
      bytes.addAll(chunk);
    }
    return parse(utf8.decode(bytes, allowMalformed: true));
  }

  static List<LocalSearchResult> parse(String body) {
    final document = html.parse(body);
    if (document.querySelector('#challenge-form') != null ||
        document.querySelector('#anomaly-modal') != null) {
      throw const FormatException('Search verification required.');
    }
    final results = <LocalSearchResult>[];
    final seen = <String>{};
    for (final element in document.querySelectorAll('.result')) {
      if (element.classes.contains('result--ad')) continue;
      final link = element.querySelector('.result__a');
      final href = link?.attributes['href'];
      if (href == null) continue;
      final redirect = Uri.tryParse(
        href.startsWith('//') ? 'https:$href' : href,
      );
      final url = redirect?.queryParameters['uddg'] ?? href;
      if (!WebCitation.validUrl(url) || !seen.add(url)) continue;
      final title = link!.text.trim();
      final snippet =
          element.querySelector('.result__snippet')?.text.trim() ?? '';
      if (title.isEmpty || snippet.isEmpty) continue;
      results.add(
        LocalSearchResult(
          title.substring(0, title.length.clamp(0, 150)),
          url,
          snippet.substring(0, snippet.length.clamp(0, 450)),
        ),
      );
      if (results.length == 4) break;
    }
    if (results.isEmpty) throw const FormatException('No usable web results.');
    return results;
  }

  void dispose() => client.close();
}
