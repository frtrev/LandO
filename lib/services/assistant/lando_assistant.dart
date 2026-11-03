import '../../models/web_research.dart';
import '../../models/chat_message.dart';
import '../../models/property.dart';

class AssistantException implements Exception {
  final String message;
  const AssistantException(this.message);
  @override
  String toString() => message;
}

class AssistantReply {
  final String text;
  final List<CalculationRecord> calculations;
  final WebResearch? research;
  const AssistantReply(this.text, this.calculations, {this.research});
}

abstract class LandoAssistant {
  Future<AssistantReply> ask({
    required Property property,
    required List<ChatMessage> history,
    required String apiKey,
    required String model,
    bool queryInternet = true,
    void Function(CalculationRecord)? onCalculation,
  });
  void dispose();
}
