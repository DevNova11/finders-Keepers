import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../providers.dart';
import '../services/image_processing.dart';
import '../services/local_store.dart';
import '../services/outbox.dart';
import '../widgets/common.dart';

/// Submit an ownership claim on a found item.
class ClaimScreen extends ConsumerStatefulWidget {
  final Item item;
  const ClaimScreen({super.key, required this.item});

  @override
  ConsumerState<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends ConsumerState<ClaimScreen> {
  final _form = GlobalKey<FormState>();
  late final List<TextEditingController> _answers;
  final _description = TextEditingController();
  String? _proofPath;
  String? _lostItemId;
  bool _declared = false;
  bool _busy = false;

  String get _draftKey => 'claim_${widget.item.id}';

  @override
  void initState() {
    super.initState();
    _answers = [
      for (final _ in widget.item.verificationQuestions) TextEditingController(),
    ];
    _restoreDraft();
    for (final c in [..._answers, _description]) {
      c.addListener(_saveDraft);
    }
  }

  @override
  void dispose() {
    for (final c in [..._answers, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final d = await LocalStore.read('drafts', _draftKey);
    if (d is! Map || !mounted) return;
    final a = List<String>.from(d['answers'] ?? []);
    for (var i = 0; i < a.length && i < _answers.length; i++) {
      _answers[i].text = a[i];
    }
    _description.text = d['description'] ?? '';
    setState(() {});
  }

  void _saveDraft() => LocalStore.write('drafts', _draftKey, {
    'answers': _answers.map((c) => c.text).toList(),
    'description': _description.text,
  });

  Future<void> _pickProof() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (x != null) setState(() => _proofPath = x.path);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_declared) {
      showSnack(context, 'Please confirm the declaration.', error: true);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Submit claim?'),
        content: const Text(
          'You get ONE claim per item, so answers cannot be guessed '
          'repeatedly. Double-check your answers before submitting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Review'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final user = ref.read(currentUserProvider)!;
    final backend = ref.read(backendProvider);
    final id = Claim.idFor(widget.item.id, user.uid);
    setState(() => _busy = true);
    try {
      if (ref.read(onlineProvider) && await backend.claimExists(id)) {
        throw Exception('You have already claimed this item.');
      }
      final images = <String>[];
      if (_proofPath != null) {
        final p = await ImageProcessing.process(File(_proofPath!));
        final dir = await LocalStore.dir('outbox/$id');
        final f = File('${dir.path}/proof.jpg');
        await f.writeAsBytes(p.jpeg, flush: true);
        images.add(f.path);
      }
      final now = DateTime.now();
      final claim = Claim(
        id: id,
        itemId: widget.item.id,
        itemTitle: widget.item.title,
        itemReporterId: widget.item.reporterId,
        claimantId: user.uid,
        claimantAlias: user.alias,
        answers: _answers.map((c) => c.text.trim()).toList(),
        description: _description.text.trim(),
        claimantLostItemId: _lostItemId,
        status: ClaimStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      await ref.read(outboxProvider.notifier).enqueue(
        PendingSubmission(
          id: id,
          kind: SubmissionKind.claim,
          payload: claim.toMap(),
          localImages: images,
          createdAt: now,
        ),
      );
      await LocalStore.delete('drafts', _draftKey);
      if (!mounted) return;
      showSnack(
        context,
        ref.read(onlineProvider)
            ? 'Claim submitted. The finder will review it.'
            : 'Claim saved offline — it will be sent when you reconnect.',
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final myLost = (ref.watch(myItemsProvider).value ?? const <Item>[])
        .where((i) => i.type == ItemType.lost && i.status.isOpen)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Claim ownership')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 48),
          children: [
            ItemCard(item: item, onTap: () {}),
            const InfoBox(
              icon: Icons.verified_user_outlined,
              text:
                  'Prove the item is yours. Your answers are compared with '
                  'secret answers set by the finder, who then approves or '
                  'rejects your claim. Only you and the finder can see this claim.',
            ),
            if (item.verificationQuestions.isNotEmpty)
              const SectionTitle('ANSWER THE FINDER\'S QUESTIONS'),
            for (var i = 0; i < item.verificationQuestions.length; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: TextFormField(
                  controller: _answers[i],
                  decoration: InputDecoration(
                    labelText: item.verificationQuestions[i],
                    labelStyle: const TextStyle(overflow: TextOverflow.visible),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Answer required' : null,
                ),
              ),
            const SectionTitle('DESCRIBE YOUR ITEM'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: TextFormField(
                controller: _description,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Unique details not mentioned in the post',
                  hintText:
                      'Scratches, stickers, contents, when/where you last had it…',
                ),
                validator: (v) => (v ?? '').trim().length < 15
                    ? 'Give at least a sentence of detail'
                    : null,
              ),
            ),
            const SectionTitle('PROOF (OPTIONAL)'),
            ListTile(
              leading: _proofPath == null
                  ? const Icon(Icons.add_photo_alternate_outlined)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: ItemImage(_proofPath),
                      ),
                    ),
              title: Text(_proofPath == null ? 'Add a proof photo' : 'Proof photo added'),
              subtitle: const Text(
                'e.g. an older photo of you with it, the box, or a receipt. '
                'Only the finder can see it.',
              ),
              trailing: _proofPath == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _proofPath = null),
                    ),
              onTap: _pickProof,
            ),
            if (myLost.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: DropdownButtonFormField<String?>(
                  initialValue: _lostItemId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Link to your lost report (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final l in myLost)
                      DropdownMenuItem(value: l.id, child: Text(l.title)),
                  ],
                  onChanged: (v) => setState(() => _lostItemId = v),
                ),
              ),
            CheckboxListTile(
              value: _declared,
              onChanged: (v) => setState(() => _declared = v ?? false),
              title: const Text(
                'I declare this item belongs to me. I understand false claims '
                'are logged against my campus account and may be reported.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.send),
                label: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Submit claim'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
