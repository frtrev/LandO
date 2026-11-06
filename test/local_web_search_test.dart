import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lando/services/assistant/local_web_search.dart';

void main() {
  test(
    'search extracts actual snippets, unwraps links, deduplicates and rejects unsafe URLs',
    () async {
      final search = LocalWebSearch(
        client: MockClient((request) async {
          expect(request.url.host, 'html.duckduckgo.com');
          expect(request.url.queryParameters['q'], 'fence cost');
          return http.Response(
            '''<div class="result"><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fcost">Fence costs</a><span class="result__snippet">Published estimate.</span></div>
<div class="result"><a class="result__a" href="javascript:alert(1)">Unsafe</a><span class="result__snippet">Bad.</span></div>
<div class="result"><a class="result__a" href="https://example.com/cost">Duplicate</a><span class="result__snippet">Again.</span></div>''',
            200,
          );
        }),
      );
      final result = await search.search('fence cost');
      expect(result, hasLength(1));
      expect(result.single.url, 'https://example.com/cost');
      expect(result.single.snippet, 'Published estimate.');
      search.dispose();
    },
  );
  test(
    'challenges and empty results are failures, never fabricated research',
    () {
      expect(
        () => LocalWebSearch.parse('<form id="challenge-form"></form>'),
        throwsFormatException,
      );
      expect(
        () => LocalWebSearch.parse('<p>Nothing found</p>'),
        throwsFormatException,
      );
    },
  );
}
