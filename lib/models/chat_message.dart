import 'web_research.dart';

class CalculationRecord {
  final String tool;
  final Map<String, dynamic> data;
  const CalculationRecord(this.tool, this.data);
  Map<String, dynamic> toJson() => {'tool': tool, 'data': data};
  factory CalculationRecord.fromJson(Map<String, dynamic> j) =>
      CalculationRecord(
        j['tool'] as String,
        Map<String, dynamic>.from(j['data'] as Map),
      );
}

class ChatMessage {
  final String role;
  final String text;
  final DateTime created;
  final List<CalculationRecord> calculations;
  final String? provider;
  final WebResearch? research;
  ChatMessage({
    required this.role,
    required this.text,
    DateTime? created,
    this.calculations = const [],
    this.provider,
    this.research,
  }) : created = created ?? DateTime.now().toUtc();
  String get contextText {
    if (research == null || role != 'assistant') return text;
    final sources = research!.citations
        .map((c) => '${c.title}: ${c.url}')
        .toSet()
        .join('\n');
    return '$text\n[Historical internet research from ${research!.checkedAt.toIso8601String()}; not a fresh lookup.]\n$sources';
  }

  Map<String, dynamic> toJson() => {
    'role': role,
    if (research != null) 'research': research!.toJson(),
    if (provider != null) 'provider': provider,
    'text': text,
    'created': created.toIso8601String(),
    'calculations': calculations.map((c) => c.toJson()).toList(),
  };
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    role: j['role'] as String,
    research: j['research'] is Map
        ? WebResearch.fromJson(Map<String, dynamic>.from(j['research'] as Map))
        : null,
    provider: j['provider'] as String?,
    text: j['text'] as String,
    created: DateTime.parse(j['created'] as String),
    calculations: ((j['calculations'] as List?) ?? [])
        .map((c) => CalculationRecord.fromJson(Map<String, dynamic>.from(c)))
        .toList(),
  );
}
