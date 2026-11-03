import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/property.dart';
import '../services/assistant/api_key_store.dart';
import '../services/assistant/openai_assistant.dart';
import '../services/assistant/gemini_assistant.dart';
import '../services/assistant/assistant_provider.dart';
import '../services/property_repository.dart';

class PropertyChatController extends ChangeNotifier {
  final String propertyId;
  final Property Function() currentProperty;
  final PropertyRepository repository;
  final ApiKeyStore keyStore;
  final LandoAssistant Function()? createAssistant;
  final List<ChatMessage> messages = [];
  final List<CalculationRecord> pendingCalculations = [];
  bool loading = true, busy = false, configured = false;
  bool _disposed = false;
  int _generation = 0;
  String? error;
  AssistantProvider provider = AssistantProvider.openai;
  String model = defaultAssistantModel;
  LandoAssistant? _active;
  Future<void> _writes = Future.value();
  PropertyChatController({
    required this.propertyId,
    required this.currentProperty,
    required this.repository,
    required this.keyStore,
    this.createAssistant,
  });
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> load() async {
    try {
      final data = await repository.preference('chat:$propertyId');
      if (data != null && data.isNotEmpty) {
        final history = (jsonDecode(data) as List)
            .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
            .where((m) => m.role == 'user' || m.role == 'assistant')
            .toList();
        messages.addAll(
          history.skip(history.length > 40 ? history.length - 40 : 0),
        );
      }
      await reloadConfiguration();
    } on Object {
      error =
          'Could not load this conversation or secure AI settings. Retry or clear this conversation.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> reloadConfiguration() async {
    provider = AssistantProvider.parse(
      await repository.preference('aiProvider'),
    );
    configured =
        (await keyStore.read(provider: provider))?.trim().isNotEmpty ?? false;
    model =
        await repository.preference(provider.modelPreference) ??
        provider.defaultModel;
    _notify();
  }

  Future<void> _persist() {
    final data = jsonEncode(messages.map((m) => m.toJson()).toList());
    final write = _writes.then(
      (_) => repository.setPreference('chat:$propertyId', data),
    );
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> send(String question, {bool retry = false}) async {
    final text = question.trim();
    if (busy || loading || text.isEmpty || text.length > 2000) {
      return;
    }
    busy = true;
    error = null;
    pendingCalculations.clear();
    final generation = ++_generation;
    _notify();
    try {
      final key = await keyStore.read(provider: provider);
      if (key == null || key.trim().isEmpty) {
        configured = false;
        throw AssistantException(
          'Add your own ${provider.label} API key in AI settings to ask LandO.',
        );
      }
      final snapshot = Property.fromJson(currentProperty().toJson());
      if (snapshot.id != propertyId) {
        throw const AssistantException(
          'This property changed. Close chat and open it again.',
        );
      }
      if (!retry) {
        messages.add(ChatMessage(role: 'user', text: text));
      }
      if (messages.length > 40) {
        messages.removeRange(0, messages.length - 40);
      }
      await _persist();
      if (_disposed || generation != _generation) {
        return;
      }
      _active =
          createAssistant?.call() ??
          (provider == AssistantProvider.gemini
              ? GeminiAssistant()
              : OpenAiAssistant());
      final reply = await _active!.ask(
        property: snapshot,
        history: List.unmodifiable(messages),
        apiKey: key,
        model: model,
        onCalculation: (record) {
          if (!_disposed && generation == _generation) {
            pendingCalculations.add(record);
            _notify();
          }
        },
      );
      if (_disposed || generation != _generation) {
        return;
      }
      messages.add(
        ChatMessage(
          role: 'assistant',
          text: reply.text,
          calculations: reply.calculations,
          provider: provider.label,
        ),
      );
      if (messages.length > 40) {
        messages.removeRange(0, messages.length - 40);
      }
      try {
        await _persist();
      } on Object {
        error = 'The answer is shown, but could not be saved on this device.';
      }
    } on Object catch (e) {
      if (!_disposed && generation == _generation) {
        error = e is AssistantException
            ? e.message
            : 'Could not read secure settings or save this conversation. Please try again.';
      }
    } finally {
      if (generation == _generation) {
        _active?.dispose();
        _active = null;
        busy = false;
        _notify();
      }
    }
  }

  String? get retryQuestion =>
      messages.isNotEmpty && messages.last.role == 'user'
      ? messages.last.text
      : null;
  void cancel() {
    _generation++;
    _active?.dispose();
    _active = null;
    busy = false;
    pendingCalculations.clear();
    error = 'Request stopped. You can retry your question.';
    _notify();
  }

  Future<void> clearHistory() async {
    if (busy) {
      return;
    }
    try {
      await _writes;
      await repository.setPreference('chat:$propertyId', '[]');
      messages.clear();
      pendingCalculations.clear();
      error = null;
    } on Object {
      error = 'Could not clear the conversation. Please try again.';
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _active?.dispose();
    super.dispose();
  }
}
