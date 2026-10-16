import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../providers.dart';
import '../services/backend.dart';
import '../services/verification.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// Finder's view of a claim: automatic answer check, evidence, decision,
/// and the handover-code check that completes the return.
class ClaimReviewScreen extends ConsumerStatefulWidget {
  final String claimId;
  const ClaimReviewScreen({super.key, required this.claimId});

  @override
  ConsumerState<ClaimReviewScreen> createState() => _ClaimReviewScreenState();
}

class _ClaimReviewScreenState extends ConsumerState<ClaimReviewScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) showSnack(context, done);
    } on WrongHandoverCode catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(Claim claim, Item item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Approve this claim?'),
        content: const Text(
          'Other pending claims on this item will be rejected. The claimant '
          'receives a one-time handover code; you will need it when you hand '
          'the item over in person.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(backendProvider).approveClaim(claim, item),
      'Claim approved. Arrange the handover via chat.',
    );
  }

  Future<void> _reject(Claim claim) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reject claim'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Reason (shown to claimant)',
            hintText: 'Answers did not match the item',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              ctrl.text.trim().isEmpty
                  ? 'Details did not match the item.'
                  : ctrl.text.trim(),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null) return;
    await _run(
      () => ref.read(backendProvider).rejectClaim(claim, reason),
      'Claim rejected.',
    );
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
            : const EmptyState(icon: Icons.lock_outline, title: 'Claim not available'),
      );
    }
    final item = ref.watch(itemProvider(claim.itemId)).value;
    final secret = ref.watch(secretProvider(claim.itemId)).value;
    final results = secret == null ? null : Verification.evaluate(claim, secret);
    final score = secret == null ? null : Verification.score(claim, secret);

    return Scaffold(
      appBar: AppBar(
        title: Text('Claim by ${claim.claimantAlias}'),
        actions: [
          IconButton(
            tooltip: 'Message claimant',
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    claim.itemTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ClaimStatusChip(claim.status),
              ],
            ),
          ),
          if (claim.flagReason != null)
            InfoBox(
              icon: Icons.warning_amber,
              color: Colors.red,
              text: 'Caution: ${claim.flagReason}',
            ),
          if (score != null) _ScoreCard(score: score),
          const SectionTitle('ANSWERS VS. YOUR SECRET ANSWERS'),
          for (var i = 0; i < claim.answers.length; i++)
            ListTile(
              leading: results == null
                  ? const Icon(Icons.help_outline)
                  : Icon(
                      results[i] ? Icons.check_circle : Icons.cancel,
                      color: results[i] ? Colors.green : Colors.red,
                    ),
              title: Text(
                i < (item?.verificationQuestions.length ?? 0)
                    ? item!.verificationQuestions[i]
                    : 'Question ${i + 1}',
              ),
              subtitle: Text('Answer: "${claim.answers[i]}"'),
            ),
          const SectionTitle('CLAIMANT\'S DESCRIPTION'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(claim.description),
          ),
          if (claim.proofImageUrl != null) ...[
            const SectionTitle('PROOF PHOTO'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(height: 220, child: ItemImage(claim.proofImageUrl)),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (claim.status == ClaimStatus.pending && item != null) ...[
            const InfoBox(
              icon: Icons.tips_and_updates_outlined,
              text:
                  'Not sure? Ask a follow-up question in chat (e.g. "what was '
                  'in the front pocket?") before deciding.',
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _reject(claim),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy || item.status != ItemStatus.found
                          ? null
                          : () => _approve(claim, item),
                      icon: const Icon(Icons.verified),
                      label: const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (claim.status == ClaimStatus.approved && item != null)
            _handoverSection(claim, item),
          if (claim.status == ClaimStatus.completed)
            const InfoBox(
              icon: Icons.celebration,
              color: Colors.green,
              text: 'Handover verified. Thanks for returning the item!',
            ),
          if (claim.status == ClaimStatus.rejected)
            InfoBox(
              icon: Icons.block,
              color: Colors.red,
              text: 'Rejected: ${claim.rejectionReason ?? ''}',
            ),
        ],
      ),
    );
  }

  Widget _handoverSection(Claim claim, Item item) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionTitle('VERIFY HANDOVER'),
      const InfoBox(
        icon: Icons.handshake_outlined,
        text:
            'Meet in a public place — we recommend '
            '${AppConfig.recommendedHandoverPoint}. Ask the claimant to read '
            'out the 6-digit code shown in their app, and enter it below '
            'BEFORE handing the item over.',
      ),
      if (claim.handoverCodeHash == null)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Waiting for the claimant to open their claim and generate the '
            'handover code…',
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: const InputDecoration(
                    labelText: 'Handover code',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (_code.text.length != 6) {
                          showSnack(context, 'Enter all 6 digits', error: true);
                          return;
                        }
                        _run(
                          () => ref
                              .read(backendProvider)
                              .completeHandover(claim, item, _code.text),
                          'Verified! Item marked as returned.',
                        );
                      },
                child: const Text('Verify'),
              ),
            ],
          ),
        ),
    ],
  );
}

class _ScoreCard extends StatelessWidget {
  final double score;
  const _ScoreCard({required this.score});

  @override
  Widget build(BuildContext context) {
    final (label, color) = score >= 0.99
        ? ('Strong match — all answers correct', Colors.green)
        : score >= 0.5
        ? ('Partial match — verify further in chat', Colors.orange)
        : ('Weak match — answers mostly wrong', Colors.red);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${(score * 100).round()}%',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(label)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: score,
              color: color,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            const Text(
              'Automatic check of answers against your hashed secret answers. '
              'The final decision is yours.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
