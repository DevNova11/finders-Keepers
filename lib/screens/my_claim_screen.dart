import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../providers.dart';
import '../services/verification.dart';
import '../widgets/common.dart';
import 'browse_screen.dart';
import 'chat_screen.dart';

/// Claimant's view of their own claim, including the one-time handover code
/// once the finder approves.
class MyClaimScreen extends ConsumerStatefulWidget {
  final String claimId;
  const MyClaimScreen({super.key, required this.claimId});

  @override
  ConsumerState<MyClaimScreen> createState() => _MyClaimScreenState();
}

class _MyClaimScreenState extends ConsumerState<MyClaimScreen> {
  String? _code;
  bool _generating = false;
  bool _syncedLostItem = false;

  /// Generates the code on this device the first time an approved claim is
  /// opened. Only the claimant ever sees the plain code.
  Future<void> _ensureCode(Claim claim) async {
    if (_code != null || _generating) return;
    _generating = true;
    final backend = ref.read(backendProvider);
    try {
      final existing = await backend.getHandoverCode(claim.id);
      if (existing != null && claim.handoverCodeHash != null) {
        if (mounted) setState(() => _code = existing);
        return;
      }
      final code = Verification.newHandoverCode();
      final salt = Verification.newSalt(8);
      await backend.saveHandoverCode(claim.id, code);
      await backend.setHandoverHash(
        claim,
        Verification.handoverHash(code, salt),
        salt,
      );
      if (mounted) setState(() => _code = code);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      _generating = false;
    }
  }

  /// Keeps the claimant's own lost report in step with the claim.
  Future<void> _syncLostItem(Claim claim) async {
    if (_syncedLostItem || claim.claimantLostItemId == null) return;
    _syncedLostItem = true;
    final backend = ref.read(backendProvider);
    final lost = await backend.watchItem(claim.claimantLostItemId!).first;
    if (lost == null) return;
    final target = claim.status == ClaimStatus.completed
        ? ItemStatus.returned
        : ItemStatus.claimed;
    if (lost.status == target || lost.status == ItemStatus.returned) return;
    try {
      await backend.setItemStatus(
        lost,
        target,
        target == ItemStatus.returned
            ? 'Recovered via verified claim'
            : 'Ownership verified on a found report',
      );
    } catch (_) {
      _syncedLostItem = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final claimAsync = ref.watch(claimProvider(widget.claimId));
    final claim = claimAsync.value;
    if (claim == null) {
      return Scaffold(
        appBar: AppBar(),
        body: claimAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(
                icon: Icons.hourglass_empty,
                title: 'Claim not synced yet',
                subtitle: 'It will appear once it reaches the server.',
              ),
      );
    }
    if (claim.status == ClaimStatus.approved) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCode(claim));
    }
    if (claim.status == ClaimStatus.approved ||
        claim.status == ClaimStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLostItem(claim));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My claim'),
        actions: [
          IconButton(
            tooltip: 'Message finder',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(claim: claim)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          ListTile(
            title: Text(
              claim.itemTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            subtitle: Text('Submitted ${timeAgo(claim.createdAt)}'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => openItem(context, claim.itemId),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ClaimStatusChip(claim.status),
            ),
          ),
          ..._statusBody(claim),
          const SectionTitle('YOUR ANSWERS'),
          for (final a in claim.answers)
            ListTile(
              dense: true,
              leading: const Icon(Icons.short_text),
              title: Text(a),
            ),
          const SectionTitle('YOUR DESCRIPTION'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(claim.description),
          ),
          if (claim.status == ClaimStatus.pending)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    await ref.read(backendProvider).withdrawClaim(claim);
                  } catch (e) {
                    if (context.mounted) {
                      showSnack(context, friendlyError(e), error: true);
                    }
                  }
                },
                child: const Text('Withdraw claim'),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _statusBody(Claim claim) => switch (claim.status) {
    ClaimStatus.pending => [
      const InfoBox(
        icon: Icons.hourglass_top,
        text:
            'The finder is reviewing your answers. They may message you with '
            'a follow-up question.',
      ),
    ],
    ClaimStatus.approved => [
      const InfoBox(
        icon: Icons.verified,
        color: Colors.green,
        text:
            'Ownership verified! Arrange a meeting via chat. Show this code '
            'ONLY to the finder in person, at the moment of handover.',
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text('HANDOVER CODE'),
              const SizedBox(height: 8),
              _code == null
                  ? const CircularProgressIndicator()
                  : SelectableText(
                      _code!,
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            letterSpacing: 10,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
              const SizedBox(height: 8),
              const Text(
                'Suggested meeting point: ${AppConfig.recommendedHandoverPoint}',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ],
    ClaimStatus.rejected => [
      InfoBox(
        icon: Icons.block,
        color: Colors.red,
        text: 'Your claim was not approved: ${claim.rejectionReason ?? ''}',
      ),
    ],
    ClaimStatus.withdrawn => [
      const InfoBox(icon: Icons.undo, text: 'You withdrew this claim.'),
    ],
    ClaimStatus.completed => [
      const InfoBox(
        icon: Icons.celebration,
        color: Colors.green,
        text: 'Item returned to you. Enjoy having it back!',
      ),
    ],
  };
}
