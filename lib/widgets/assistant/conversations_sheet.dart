import 'package:flutter/material.dart';
import '../../models/chat_conversation.dart';

class ConversationsSheet extends StatelessWidget {
  final List<ChatConversation> conversations;
  final String activeId;
  final ValueChanged<ChatConversation> onOpen, onRename, onDelete;
  final VoidCallback onNew;
  const ConversationsSheet({
    super.key,
    required this.conversations,
    required this.activeId,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onNew,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Conversations',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('New'),
              ),
            ],
          ),
        ),
        for (final conversation in conversations)
          ListTile(
            key: ValueKey(conversation.id),
            isThreeLine: true,
            leading: Icon(
              conversation.id == activeId
                  ? Icons.chat_bubble
                  : Icons.chat_bubble_outline,
            ),
            title: Text(
              conversation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${conversation.messages.length} messages · ${conversation.modified.toLocal().toString().split('.').first}\n${conversation.messages.isEmpty ? 'No messages yet' : conversation.messages.last.text.replaceAll(RegExp(r'\s+'), ' ')}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onOpen(conversation),
            trailing: PopupMenuButton<String>(
              tooltip: 'Manage ${conversation.title}',
              onSelected: (action) => action == 'rename'
                  ? onRename(conversation)
                  : onDelete(conversation),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
      ],
    ),
  );
}
