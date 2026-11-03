import 'package:flutter/material.dart';
import '../../controllers/property_chat_controller.dart';
import '../../models/property.dart';
import '../../services/assistant/api_key_store.dart';
import '../../services/assistant/openai_assistant.dart';
import '../../services/property_repository.dart';
import 'ai_settings_sheet.dart';
import 'calculation_card.dart';

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
  @override
  void initState() {
    super.initState();
    chat.addListener(refresh);
    chat.load();
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
        title: const Text('Clear this property chat?'),
        content: const Text(
          'This removes its chat history from this device. Your property and saved shapes remain.',
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
                    onPressed: chat.busy ? null : configure,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  IconButton(
                    tooltip: 'Clear chat history',
                    onPressed: chat.busy || chat.messages.isEmpty
                        ? null
                        : clear,
                    icon: const Icon(Icons.delete_outline),
                  ),
                  IconButton(
                    tooltip: 'Close chat',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: chat.loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: scroll,
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Ask about your boundary, saved areas, measurements, or a project. LandO calculates quantities; the assistant explains them.',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Provider: ${chat.provider.label} · ${chat.model}\nSending shares your messages, recent conversation and property data with ${chat.provider.label}. Results are planning estimates, not legal surveys.',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (!chat.configured)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: FilledButton.tonalIcon(
                              onPressed: configure,
                              icon: const Icon(Icons.key),
                              label: Text('Set up ${chat.provider.label} key'),
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
                                    onPressed: chat.busy
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
                                  message.role == 'user'
                                      ? 'You'
                                      : message.provider == null
                                      ? 'LandO'
                                      : 'LandO · ${message.provider}',
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
                      enabled: !chat.loading && !chat.busy && chat.configured,
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
                    onPressed: chat.loading || chat.busy || !chat.configured
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
