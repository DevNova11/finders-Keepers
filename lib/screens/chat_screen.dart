import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../providers.dart';
import '../widgets/common.dart';

final _contactPattern = RegExp(
  r'(\+?\d[\d\s-]{8,}\d)|([^@\s]+@[^@\s]+\.[a-z]{2,})',
  caseSensitive: false,
);

/// Claim-scoped chat between finder and claimant. Only the two parties can
/// read it, so nobody needs to share a phone number or social handle.
class ChatScreen extends ConsumerStatefulWidget {
  final Claim claim;
  const ChatScreen({super.key, required this.claim});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    if (_contactPattern.hasMatch(text)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Share contact details?'),
          content: const Text(
            'This looks like a phone number or e-mail. You don\'t need to '
            'share personal contact details — you can arrange everything here.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Edit message'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Send anyway'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final user = ref.read(currentUserProvider)!;
    _text.clear();
    try {
      await ref.read(backendProvider).sendMessage(
        widget.claim.id,
        ChatMessage(
          id: const Uuid().v4(),
          senderId: user.uid,
          senderAlias: user.alias,
          text: text,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      _text.text = text;
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final messages = ref.watch(messagesProvider(widget.claim.id)).value ?? [];
    final scheme = Theme.of(context).colorScheme;
    final other = user.uid == widget.claim.claimantId ? 'finder' : 'claimant';
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with $other'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.claim.itemTitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: messages.isEmpty
                ? const EmptyState(
                    icon: Icons.forum_outlined,
                    title: 'No messages yet',
                    subtitle:
                        'Agree on a public meeting place. Never send money or '
                        'personal documents.',
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[messages.length - 1 - i];
                      final mine = m.senderId == user.uid;
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 280),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.text),
                              const SizedBox(height: 2),
                              Text(
                                '${mine ? 'You' : m.senderAlias} · ${timeAgo(m.createdAt)}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message (no phone numbers needed)',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
