import 'package:flutter/material.dart';
import '../../controllers/property_chat_controller.dart';
import '../../models/property.dart';
import '../../services/assistant/api_key_store.dart';
import '../../services/assistant/openai_assistant.dart';
import '../../services/property_repository.dart';
import 'ai_settings_sheet.dart';
import 'calculation_card.dart';
import 'conversations_sheet.dart';
import '../../models/chat_conversation.dart';

class PropertyChatSheet extends StatefulWidget {
  final Property Function() currentProperty;
  final PropertyRepository repository;
  final ApiKeyStore keyStore;
  final LandoAssistant Function()? createAssistant;
  const PropertyChatSheet({
    super.key,
    required this.currentProperty,
    required this.repository,
    required this.keyStore,
    this.createAssistant,
  });
  @override
  State<PropertyChatSheet> createState() => _PropertyChatSheetState();
}

class _PropertyChatSheetState extends State<PropertyChatSheet> {
  late final chat = PropertyChatController(
    propertyId: widget.currentProperty().id,
    currentProperty: widget.currentProperty,
    repository: widget.repository,
    keyStore: widget.keyStore,
    createAssistant: widget.createAssistant,
  );
  final input = TextEditingController();
  final scroll = ScrollController();
  final Map<String, String> _drafts = {};
  @override
  void initState() {
    super.initState();
    chat.addListener(refresh);
    chat.load().then((_) => showLatest());
  }

  void refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    chat.removeListener(refresh);
    chat.dispose();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> configure() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => AiSettingsSheet(
        keyStore: widget.keyStore,
        repository: widget.repository,
      ),
    );
    if (mounted) {
      try {
        await chat.reloadConfiguration();
      } on Object {
        setState(() => chat.error = 'Could not read secure AI settings.');
      }
    }
  }

  void send([String? suggestion]) {
    final question = (suggestion ?? input.text).trim();
    if (question.isEmpty) {
      return;
    }
    input.clear();
    FocusScope.of(context).unfocus();
    chat.send(question).then((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text(
          'This clears only the current conversation. Your other conversations, property and saved shapes remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await chat.clearHistory();
    }
  }

  void showLatest() {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> startConversation() async {
    if (chat.unavailable) {
      return;
    }
    _drafts[chat.activeConversation.id] = input.text;
    if (await chat.newConversation() && mounted) {
      input.clear();
      FocusScope.of(context).unfocus();
      showLatest();
    }
  }

  Future<void> openConversation(String id) async {
    if (chat.unavailable) {
      return;
    }
    _drafts[chat.activeConversation.id] = input.text;
    if (await chat.openConversation(id) && mounted) {
      input.text = _drafts[id] ?? '';
      FocusScope.of(context).unfocus();
      showLatest();
    }
  }

  Future<void> renameConversation(ChatConversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Conversation title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(c, controller.text.trim());
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (title != null) {
      await chat.renameConversation(conversation.id, title);
    }
  }

  Future<void> deleteConversation(ChatConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text('Delete “${conversation.title}”?'),
        content: const Text(
          'This removes only this conversation from this device. Your property and other conversations remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final previous = chat.activeConversation.id;
      if (await chat.deleteConversation(conversation.id) && mounted) {
        _drafts.remove(conversation.id);
        if (previous != chat.activeConversation.id) {
          input.text = _drafts[chat.activeConversation.id] ?? '';
          showLatest();
        }
      }
    }
  }

  Future<void> showConversations() async {
    final action = await showModalBottomSheet<({String action, String? id})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .75,
      ),
      builder: (c) => ConversationsSheet(
        conversations: chat.conversations,
        activeId: chat.activeConversation.id,
        onNew: () => Navigator.pop(c, (action: 'new', id: null)),
        onOpen: (conversation) =>
            Navigator.pop(c, (action: 'open', id: conversation.id)),
        onRename: (conversation) =>
            Navigator.pop(c, (action: 'rename', id: conversation.id)),
        onDelete: (conversation) =>
            Navigator.pop(c, (action: 'delete', id: conversation.id)),
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    if (action.action == 'new') {
      await startConversation();
      return;
    }
    final conversation = chat.conversations.firstWhere(
      (c) => c.id == action.id,
    );
    if (action.action == 'open') {
      await openConversation(conversation.id);
    }
    if (action.action == 'rename') {
      await renameConversation(conversation);
    }
    if (action.action == 'delete') {
      await deleteConversation(conversation);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ask LandO',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          widget.currentProperty().name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'AI settings',
                    onPressed: chat.unavailable ? null : configure,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  IconButton(
                    tooltip: 'Close chat',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      chat.activeConversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'New conversation',
                    onPressed: chat.unavailable ? null : startConversation,
                    icon: const Icon(Icons.add_comment_outlined),
                  ),
                  IconButton(
                    tooltip: 'Conversations',
                    onPressed: chat.unavailable ? null : showConversations,
                    icon: const Icon(Icons.history),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Conversation options',
                    enabled: !chat.unavailable,
                    onSelected: (action) {
                      if (action == 'rename') {
                        renameConversation(chat.activeConversation);
                      } else if (action == 'delete') {
                        deleteConversation(chat.activeConversation);
                      } else {
                        clear();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename conversation'),
                      ),
                      PopupMenuItem(
                        value: 'clear',
                        enabled: chat.messages.isNotEmpty,
                        child: const Text('Clear conversation'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete conversation'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: chat.loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      key: ValueKey(chat.activeConversation.id),
                      controller: scroll,
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Ask about your boundary, saved areas, measurements, or a project. LandO calculates quantities; the assistant explains them.',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sending shares your messages, recent conversation and property data with your configured AI service. Results are planning estimates, not legal surveys.',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (!chat.configured)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: FilledButton.tonalIcon(
                              onPressed: configure,
                              icon: const Icon(Icons.key),
                              label: const Text('Set up LandO'),
                            ),
                          ),
                        if (chat.messages.isEmpty && chat.configured)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final question in [
                                  'How many acres is my property?',
                                  'How long is my boundary?',
                                  'Compare my saved areas.',
                                  'Help me estimate fencing.',
                                ])
                                  ActionChip(
                                    label: Text(question),
                                    onPressed: chat.unavailable
                                        ? null
                                        : () => send(question),
                                  ),
                              ],
                            ),
                          ),
                        for (final message in chat.messages)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.role == 'user' ? 'You' : 'LandO',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: 4),
                                SelectableText(message.text),
                                if (message.calculations.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Property snapshot · ${message.created.toLocal().toString().split('.').first}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  for (final record in message.calculations)
                                    CalculationCard(record: record),
                                ],
                              ],
                            ),
                          ),
                        if (chat.busy) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          Text(
                            'LandO is checking your property and calculations… (${chat.pendingCalculations.length} results)',
                          ),
                          TextButton(
                            onPressed: chat.cancel,
                            child: const Text('Stop request'),
                          ),
                        ],
                        if (!chat.unavailable &&
                            chat.error == null &&
                            chat.retryQuestion != null &&
                            chat.configured)
                          TextButton(
                            onPressed: () =>
                                chat.send(chat.retryQuestion!, retry: true),
                            child: const Text('Continue last question'),
                          ),
                        if (chat.error != null) ...[
                          Text(
                            chat.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          if (!chat.busy &&
                              chat.retryQuestion != null &&
                              chat.configured)
                            TextButton(
                              onPressed: () =>
                                  chat.send(chat.retryQuestion!, retry: true),
                              child: const Text('Retry question'),
                            ),
                        ],
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      enabled: !chat.unavailable && chat.configured,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: 'Ask LandO about my property…',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onSubmitted: (_) => send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send question',
                    onPressed: chat.unavailable || !chat.configured
                        ? null
                        : () => send(),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
