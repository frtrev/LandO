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
  ChatMessage({
    required this.role,
    required this.text,
    DateTime? created,
    this.calculations = const [],
    this.provider,
  }) : created = created ?? DateTime.now().toUtc();
  Map<String, dynamic> toJson() => {
    'role': role,
    if (provider != null) 'provider': provider,
    'text': text,
    'created': created.toIso8601String(),
    'calculations': calculations.map((c) => c.toJson()).toList(),
  };
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    role: j['role'] as String,
    provider: j['provider'] as String?,
    text: j['text'] as String,
    created: DateTime.parse(j['created'] as String),
    calculations: ((j['calculations'] as List?) ?? [])
        .map((c) => CalculationRecord.fromJson(Map<String, dynamic>.from(c)))
        .toList(),
  );
}
