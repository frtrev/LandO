import 'dart:convert';
import 'chat_message.dart';
import 'property.dart' show newId;

class ChatConversation {
  final String id;
  String title;
  bool autoTitle;
  final DateTime created;
  DateTime modified;
  final List<ChatMessage> messages;
  ChatConversation({
    required this.id,
    required this.title,
    required this.created,
    required this.modified,
    this.autoTitle = true,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];
  factory ChatConversation.empty() {
    final now = DateTime.now().toUtc();
    return ChatConversation(
      id: newId(),
      title: 'New conversation',
      created: now,
      modified: now,
    );
  }
  static String titleFromQuestion(String text) {
    final title = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return title.length <= 70 ? title : '${title.substring(0, 69)}…';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'autoTitle': autoTitle,
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };
  factory ChatConversation.fromJson(Map<String, dynamic> j) => ChatConversation(
    id: j['id'] as String,
    title: j['title'] as String,
    autoTitle: j['autoTitle'] as bool? ?? true,
    created: DateTime.parse(j['created'] as String),
    modified: DateTime.parse(j['modified'] as String),
    messages: (j['messages'] as List)
        .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList(),
  );
}

/// One atomic SQLite preference per property. Version 2 upgrades the original
/// message list without resetting or truncating any existing messages.
class ConversationArchive {
  final List<ChatConversation> conversations;
  String activeId;
  ConversationArchive({required this.conversations, required this.activeId});
  factory ConversationArchive.empty() {
    final conversation = ChatConversation.empty();
    return ConversationArchive(
      conversations: [conversation],
      activeId: conversation.id,
    );
  }
  ChatConversation get active =>
      conversations.firstWhere((c) => c.id == activeId);
  List<ChatConversation> get newestFirst =>
      List.of(conversations)..sort((a, b) => b.modified.compareTo(a.modified));
  Map<String, dynamic> toJson() => {
    'version': 2,
    'activeId': activeId,
    'conversations': conversations.map((c) => c.toJson()).toList(),
  };
  factory ConversationArchive.fromStored(String? data) {
    if (data == null || data.isEmpty) {
      return ConversationArchive.empty();
    }
    final decoded = jsonDecode(data);
    if (decoded is List) {
      final messages = decoded
          .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .toList();
      if (messages.isEmpty) {
        return ConversationArchive.empty();
      }
      final firstQuestion = messages.where((m) => m.role == 'user').firstOrNull;
      final conversation = ChatConversation(
        id: newId(),
        title: firstQuestion == null
            ? 'Previous conversation'
            : ChatConversation.titleFromQuestion(firstQuestion.text),
        created: messages.first.created,
        modified: messages.last.created,
        messages: messages,
      );
      return ConversationArchive(
        conversations: [conversation],
        activeId: conversation.id,
      );
    }
    if (decoded is! Map || decoded['version'] != 2) {
      throw const FormatException('Unsupported conversation archive.');
    }
    final conversations = (decoded['conversations'] as List)
        .map((c) => ChatConversation.fromJson(Map<String, dynamic>.from(c)))
        .toList();
    if (conversations.isEmpty) {
      return ConversationArchive.empty();
    }
    if (conversations.map((c) => c.id).toSet().length != conversations.length) {
      throw const FormatException('Duplicate conversation IDs.');
    }
    final archive = ConversationArchive(
      conversations: conversations,
      activeId: decoded['activeId'] as String,
    );
    if (!conversations.any((c) => c.id == archive.activeId)) {
      archive.activeId = archive.newestFirst.first.id;
    }
    return archive;
  }
}
