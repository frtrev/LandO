/// Source annotations supplied by the search service, never invented from text.
class WebCitation {
  final int start, end;
  final String url, title;
  const WebCitation({
    required this.start,
    required this.end,
    required this.url,
    required this.title,
  });
  static bool validUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'url': url,
    'title': title,
  };
  static WebCitation? parse(Map data, {int offset = 0}) {
    final url = data['url'];
    final start = data['start_index'], end = data['end_index'];
    if (url is! String ||
        !validUrl(url) ||
        start is! int ||
        end is! int ||
        start < 0 ||
        end < start) {
      return null;
    }
    return WebCitation(
      start: start + offset,
      end: end + offset,
      url: url,
      title: data['title'] is String
          ? data['title'] as String
          : Uri.parse(url).host,
    );
  }

  factory WebCitation.fromJson(Map<String, dynamic> json) => WebCitation(
    start: json['start'] as int,
    end: json['end'] as int,
    url: json['url'] as String,
    title: json['title'] as String,
  );
}

class WebResearch {
  final DateTime checkedAt;
  final List<WebCitation> citations;
  final List<String> searchSuggestions;
  const WebResearch({
    required this.checkedAt,
    this.citations = const [],
    this.searchSuggestions = const [],
  });
  static const disclaimer =
      'Planning estimate based on online information, which may be incomplete, outdated or inaccurate. Local labor and site conditions vary. Confirm pricing with contractor quotes; property values are not appraisals.';
  Map<String, dynamic> toJson() => {
    'checkedAt': checkedAt.toIso8601String(),
    'citations': citations.map((c) => c.toJson()).toList(),
    'searchSuggestions': searchSuggestions,
  };
  factory WebResearch.fromJson(Map<String, dynamic> json) => WebResearch(
    checkedAt: DateTime.parse(json['checkedAt'] as String),
    citations: (json['citations'] as List? ?? [])
        .map((c) => WebCitation.fromJson(Map<String, dynamic>.from(c as Map)))
        .where(
          (c) =>
              c.start >= 0 && c.end >= c.start && WebCitation.validUrl(c.url),
        )
        .toList(),
    searchSuggestions: (json['searchSuggestions'] as List? ?? [])
        .cast<String>(),
  );
}
