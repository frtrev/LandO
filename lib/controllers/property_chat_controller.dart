import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/chat_conversation.dart';
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
  ConversationArchive _archive = ConversationArchive.empty();
  ChatConversation get activeConversation => _archive.active;
  List<ChatMessage> get messages => activeConversation.messages;
  List<ChatConversation> get conversations =>
      List.unmodifiable(_archive.newestFirst);
  bool managing = false;
  bool _historyReady = false;
  bool get unavailable => loading || busy || managing || !_historyReady;
  final List<CalculationRecord> pendingCalculations = [];
  bool loading = true, busy = false, configured = false;
  bool _disposed = false;
  int _generation = 0;
  String? error;
  AssistantProvider provider = AssistantProvider.openai;
  String model = defaultAssistantModel;
  bool queryInternet = true;
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
      _archive = ConversationArchive.fromStored(data);
      // Atomic replacement publishes both migrated conversations and selection.
      // On failure, the original preference remains intact.
      await _persist();
      _historyReady = true;
      await reloadConfiguration();
    } on Object {
      error =
          'Could not load conversations or secure AI settings. Close chat and try again. Stored conversations have not been cleared.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> reloadConfiguration() async {
    queryInternet = await repository.preference('queryInternet') != 'false';
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
    final data = jsonEncode(_archive.toJson());
    final write = _writes.then(
      (_) => repository.setPreference('chat:$propertyId', data),
    );
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> send(String question, {bool retry = false}) async {
    final text = question.trim();
    if (unavailable || text.isEmpty || text.length > 2000) {
      return;
    }
    busy = true;
    error = null;
    pendingCalculations.clear();
    final generation = ++_generation;
    final conversation = activeConversation;
    _notify();
    try {
      final key = await keyStore.read(provider: provider);
      if (key == null || key.trim().isEmpty) {
        configured = false;
        throw AssistantException(
          'Add your API key in AI settings to ask LandO.',
        );
      }
      final snapshot = Property.fromJson(currentProperty().toJson());
      if (snapshot.id != propertyId) {
        throw const AssistantException(
          'This property changed. Close chat and open it again.',
        );
      }
      if (!retry) {
        if (conversation.messages.isEmpty && conversation.autoTitle) {
          conversation.title = ChatConversation.titleFromQuestion(text);
        }
        conversation.messages.add(ChatMessage(role: 'user', text: text));
      }
      conversation.modified = DateTime.now().toUtc();
      await _persist();
      if (_disposed ||
          generation != _generation ||
          activeConversation.id != conversation.id) {
        return;
      }
      _active =
          createAssistant?.call() ??
          (provider == AssistantProvider.gemini
              ? GeminiAssistant()
              : OpenAiAssistant());
      final reply = await _active!.ask(
        property: snapshot,
        history: List.unmodifiable(conversation.messages),
        apiKey: key,
        model: model,
        queryInternet: queryInternet,
        onCalculation: (record) {
          if (!_disposed && generation == _generation) {
            pendingCalculations.add(record);
            _notify();
          }
        },
      );
      if (_disposed ||
          generation != _generation ||
          activeConversation.id != conversation.id) {
        return;
      }
      conversation.messages.add(
        ChatMessage(
          role: 'assistant',
          text: reply.text,
          calculations: reply.calculations,
          research: reply.research,
          provider: provider.label,
        ),
      );
      conversation.modified = DateTime.now().toUtc();
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

  /// Block navigation during a request, and roll back any management edit if
  /// its atomic SQLite archive write fails. No other conversation is cleared.
  Future<bool> _manage(void Function() edit, String failureMessage) async {
    if (unavailable) {
      return false;
    }
    managing = true;
    _generation++;
    error = null;
    final before = ConversationArchive.fromStored(
      jsonEncode(_archive.toJson()),
    );
    _notify();
    try {
      edit();
      pendingCalculations.clear();
      await _persist();
      return true;
    } on Object {
      _archive = before;
      error = failureMessage;
      return false;
    } finally {
      managing = false;
      _notify();
    }
  }

  Future<bool> newConversation() => _manage(() {
    final conversation = ChatConversation.empty();
    _archive.conversations.add(conversation);
    _archive.activeId = conversation.id;
  }, 'Could not create a conversation. Please try again.');
  Future<bool> openConversation(String id) => _manage(() {
    if (!_archive.conversations.any((c) => c.id == id)) {
      throw StateError('Conversation not found');
    }
    _archive.activeId = id;
  }, 'Could not open that conversation. Please try again.');
  Future<bool> renameConversation(String id, String title) => _manage(() {
    final name = title.trim();
    if (name.isEmpty || name.length > 100) {
      throw const FormatException('Enter a title of 1–100 characters.');
    }
    final conversation = _archive.conversations.firstWhere((c) => c.id == id);
    conversation.title = name;
    conversation.autoTitle = false;
  }, 'Could not rename that conversation. Please try again.');
  Future<bool> deleteConversation(String id) => _manage(() {
    if (!_archive.conversations.any((c) => c.id == id)) {
      throw StateError('Conversation not found');
    }
    _archive.conversations.removeWhere((c) => c.id == id);
    if (_archive.conversations.isEmpty) {
      _archive = ConversationArchive.empty();
    } else if (_archive.activeId == id) {
      _archive.activeId = _archive.newestFirst.first.id;
    }
  }, 'Could not delete that conversation. Please try again.');
  Future<void> clearHistory() async {
    await _manage(() {
      messages.clear();
      activeConversation.modified = DateTime.now().toUtc();
    }, 'Could not clear this conversation. Please try again.');
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _active?.dispose();
    super.dispose();
  }
}
