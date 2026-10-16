import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../providers.dart';
import '../services/image_processing.dart';
import '../services/local_store.dart';
import '../services/matching.dart';
import '../services/outbox.dart';
import '../services/verification.dart';
import '../widgets/common.dart';
import 'map_screen.dart';

class _QA {
  final q = TextEditingController();
  final a = TextEditingController();
  void dispose() {
    q.dispose();
    a.dispose();
  }
}

/// Report a lost or found item. The form autosaves a draft (including
/// photos) on every change so an interrupted report — app closed, phone
/// died, call came in — is restored the next time the form is opened.
class ReportScreen extends ConsumerStatefulWidget {
  final ItemType type;

  /// When answering a lost report with "I found this".
  final Item? linkedLostItem;

  const ReportScreen({super.key, required this.type, this.linkedLostItem});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _color = TextEditingController();
  final _notes = TextEditingController();
  final List<_QA> _questions = [];
  final List<String> _images = [];
  String _category = 'other';
  bool _blur = false;
  bool _blurTouched = false;
  DateTime _occurredAt = DateTime.now();
  String _locationName = AppConfig.landmarks.first.name;
  LatLng _point = AppConfig.landmarks.first.position;
  bool _submitting = false;
  bool _restored = false;
  Timer? _debounce;

  bool get _isFound => widget.type == ItemType.found;
  String get _draftKey => widget.linkedLostItem == null
      ? 'report_${widget.type.name}'
      : 'report_link_${widget.linkedLostItem!.id}';

  @override
  void initState() {
    super.initState();
    final l = widget.linkedLostItem;
    if (l != null) {
      _title.text = l.title;
      _category = l.category;
      _color.text = l.color;
      _blur = l.categoryInfo.sensitive;
    }
    if (_isFound) _addQuestion();
    for (final c in [_title, _description, _color, _notes]) {
      c.addListener(_scheduleDraftSave);
    }
    _loadDraft();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_title, _description, _color, _notes]) {
      c.dispose();
    }
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  // ---- Draft persistence ----

  Future<void> _loadDraft() async {
    final d = await LocalStore.read('drafts', _draftKey);
    if (d is! Map || !mounted) return;
    setState(() {
      _title.text = d['title'] ?? _title.text;
      _description.text = d['description'] ?? '';
      _color.text = d['color'] ?? _color.text;
      _notes.text = d['notes'] ?? '';
      _category = d['category'] ?? _category;
      _blur = d['blur'] ?? _blur;
      _blurTouched = d['blurTouched'] ?? false;
      _occurredAt = parseDate(d['occurredAt']) ?? _occurredAt;
      _locationName = d['locationName'] ?? _locationName;
      _point = LatLng(
        (d['lat'] as num?)?.toDouble() ?? _point.latitude,
        (d['lng'] as num?)?.toDouble() ?? _point.longitude,
      );
      _images
        ..clear()
        ..addAll(
          List<String>.from(d['images'] ?? [])
              .where((p) => File(p).existsSync()),
        );
      final qs = List.from(d['questions'] ?? []);
      if (qs.isNotEmpty) {
        for (final q in _questions) {
          q.dispose();
        }
        _questions.clear();
        for (final m in qs) {
          final qa = _QA();
          qa.q.text = m['q'] ?? '';
          qa.a.text = m['a'] ?? '';
          qa.q.addListener(_scheduleDraftSave);
          qa.a.addListener(_scheduleDraftSave);
          _questions.add(qa);
        }
      }
      _restored = true;
    });
  }

  void _scheduleDraftSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _saveDraft() => LocalStore.write('drafts', _draftKey, {
    'title': _title.text,
    'description': _description.text,
    'color': _color.text,
    'notes': _notes.text,
    'category': _category,
    'blur': _blur,
    'blurTouched': _blurTouched,
    'occurredAt': _occurredAt,
    'locationName': _locationName,
    'lat': _point.latitude,
    'lng': _point.longitude,
    'images': _images,
    'questions': [
      for (final q in _questions) {'q': q.q.text, 'a': q.a.text},
    ],
  });

  Future<void> _discardDraft() async {
    await LocalStore.delete('drafts', _draftKey);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReportScreen(
          type: widget.type,
          linkedLostItem: widget.linkedLostItem,
        ),
      ),
    );
  }

  void _update(VoidCallback f) {
    setState(f);
    _scheduleDraftSave();
  }

  // ---- Form actions ----

  void _addQuestion([String text = '']) {
    if (_questions.length >= AppConfig.maxVerificationQuestions) return;
    final qa = _QA()..q.text = text;
    qa.q.addListener(_scheduleDraftSave);
    qa.a.addListener(_scheduleDraftSave);
    setState(() => _questions.add(qa));
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_images.length >= AppConfig.maxImagesPerItem) return;
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 90,
      );
      if (x == null) return;
      // Copy into app storage so the draft survives cache clearing.
      final dir = await LocalStore.dir('drafts/images');
      final dest = '${dir.path}/${const Uuid().v4()}.jpg';
      await File(x.path).copy(dest);
      _update(() => _images.add(dest));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not get image: $e', error: true);
    }
  }

  Future<void> _useMyLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) showSnack(context, 'Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final here = LatLng(pos.latitude, pos.longitude);
      // Name it after the nearest landmark for readability.
      final nearest = AppConfig.landmarks.reduce(
        (a, b) =>
            const Distance().distance(a.position, here) <
                const Distance().distance(b.position, here)
            ? a
            : b,
      );
      _update(() {
        _point = here;
        _locationName = 'Near ${nearest.name}';
      });
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Could not get location: $e', error: true);
      }
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    final t = time ?? TimeOfDay.fromDateTime(_occurredAt);
    var dt = DateTime(date.year, date.month, date.day, t.hour, t.minute);
    if (dt.isAfter(DateTime.now())) dt = DateTime.now();
    _update(() => _occurredAt = dt);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final user = ref.read(currentUserProvider)!;
    setState(() => _submitting = true);
    try {
      final id = const Uuid().v4();
      // Process photos locally first (resize, strip EXIF, blur, hash), so
      // everything heavy is done even if we're offline right now.
      final outDir = await LocalStore.dir('outbox/$id');
      final processed = <String>[];
      final hashes = <String>[];
      for (var i = 0; i < _images.length; i++) {
        final p = await ImageProcessing.process(File(_images[i]), blur: _blur);
        final f = File('${outDir.path}/$i.jpg');
        await f.writeAsBytes(p.jpeg, flush: true);
        processed.add(f.path);
        hashes.add(p.dHash);
      }

      final now = DateTime.now();
      final status = _isFound ? ItemStatus.found : ItemStatus.lost;
      final questions = _isFound
          ? _questions.where((q) => q.q.text.trim().isNotEmpty).toList()
          : <_QA>[];
      final item = Item(
        id: id,
        type: widget.type,
        title: _title.text.trim(),
        description: _description.text.trim(),
        category: _category,
        color: _color.text.trim(),
        status: status,
        locationName: _locationName,
        lat: approximate(_point.latitude),
        lng: approximate(_point.longitude),
        occurredAt: _occurredAt,
        createdAt: now,
        updatedAt: now,
        reporterId: user.uid,
        reporterAlias: user.alias,
        imageHashes: hashes,
        keywords: extractKeywords([
          _title.text,
          _description.text,
          _color.text,
          _locationName,
          ItemCategory.byId(_category).label,
        ]),
        verificationQuestions: questions.map((q) => q.q.text.trim()).toList(),
        linkedItemId: widget.linkedLostItem?.id,
        history: [
          StatusEvent(
            status,
            now,
            widget.linkedLostItem != null
                ? 'Reported as found in response to a lost post'
                : 'Reported',
          ),
        ],
      );
      final secret = Verification.buildSecret(
        expectedAnswers: questions.map((q) => q.a.text).toList(),
        exactLat: _point.latitude,
        exactLng: _point.longitude,
        privateNotes: _notes.text.trim(),
      );

      await ref
          .read(outboxProvider.notifier)
          .enqueue(
            PendingSubmission(
              id: id,
              kind: SubmissionKind.item,
              payload: item.toMap(),
              secret: secret.toMap(),
              localImages: processed,
              createdAt: now,
            ),
          );
      await LocalStore.delete('drafts', _draftKey);
      for (final p in _images) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
      if (!mounted) return;
      final online = ref.read(onlineProvider);
      showSnack(
        context,
        online
            ? 'Report submitted — uploading…'
            : 'Saved offline. It will upload automatically when you reconnect.',
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final cat = ItemCategory.byId(_category);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isFound ? 'Report found item' : 'Report lost item'),
        actions: [
          if (_restored)
            TextButton(
              onPressed: _discardDraft,
              child: const Text('Discard draft'),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            if (_restored)
              const InfoBox(
                icon: Icons.restore,
                text: 'Your unfinished report was restored.',
              ),
            if (widget.linkedLostItem != null)
              InfoBox(
                icon: Icons.link,
                text:
                    'You are responding to "${widget.linkedLostItem!.title}". '
                    'The owner will be notified and must answer your secret '
                    'questions to claim it.',
              ),
            const SectionTitle('WHAT'),
            _pad(
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Black JBL earphones',
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 3 ? 'Add a short title' : null,
              ),
            ),
            _pad(
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in ItemCategory.all)
                    DropdownMenuItem(
                      value: c.id,
                      child: Row(
                        children: [
                          Icon(c.icon, size: 18),
                          const SizedBox(width: 8),
                          Text(c.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => _update(() {
                  _category = v!;
                  if (!_blurTouched) _blur = ItemCategory.byId(v).sensitive;
                }),
              ),
            ),
            _pad(
              TextFormField(
                controller: _color,
                decoration: const InputDecoration(labelText: 'Main colour'),
              ),
            ),
            _pad(
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Public description',
                  helperText: _isFound
                      ? 'Keep it general — hold back details the owner can '
                            'use to prove ownership.'
                      : 'Describe distinguishing features.',
                  helperMaxLines: 2,
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 5 ? 'Add a description' : null,
              ),
            ),
            const SectionTitle('PHOTOS'),
            if (!ref.watch(backendProvider).supportsPhotoUpload)
              const InfoBox(
                icon: Icons.image_search,
                text:
                    'Photos stay on your phone. Only an anonymous image '
                    'fingerprint is shared, used to find matching reports.',
              ),
            if (_isFound && cat.sensitive)
              const InfoBox(
                icon: Icons.privacy_tip_outlined,
                color: Colors.orange,
                text:
                    'Sensitive item: never photograph names, ID numbers, cards '
                    'or screens. Photos are blurred by default.',
              ),
            SizedBox(
              height: 110,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (var i = 0; i < _images.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 100,
                              height: 100,
                              child: ImageFiltered(
                                enabled: _blur,
                                imageFilter: _blurFilter,
                                child: ItemImage(_images[i]),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton.filledTonal(
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  _update(() => _images.removeAt(i)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_images.length < AppConfig.maxImagesPerItem) ...[
                    _AddPhotoTile(
                      icon: Icons.photo_camera_outlined,
                      label: 'Camera',
                      onTap: () => _pickImage(ImageSource.camera),
                    ),
                    _AddPhotoTile(
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
                      onTap: () => _pickImage(ImageSource.gallery),
                    ),
                  ],
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Blur photos for privacy'),
              subtitle: const Text(
                'Location metadata (EXIF/GPS) is always removed.',
              ),
              value: _blur,
              onChanged: (v) => _update(() {
                _blur = v;
                _blurTouched = true;
              }),
            ),
            const SectionTitle('WHERE & WHEN'),
            _pad(
              DropdownButtonFormField<String>(
                initialValue:
                    AppConfig.landmarks.any((l) => l.name == _locationName)
                    ? _locationName
                    : null,
                isExpanded: true,
                hint: Text(_locationName),
                decoration: const InputDecoration(labelText: 'Campus location'),
                items: [
                  for (final l in AppConfig.landmarks)
                    DropdownMenuItem(value: l.name, child: Text(l.name)),
                ],
                onChanged: (v) => _update(() {
                  final l = AppConfig.landmarks.firstWhere((e) => e.name == v);
                  _locationName = l.name;
                  _point = l.position;
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 200,
                  child: FlutterMap(
                    key: ValueKey(_point),
                    options: MapOptions(
                      initialCenter: _point,
                      initialZoom: 17,
                      onTap: (_, p) => _update(() {
                        _point = p;
                        if (!_locationName.startsWith('Near ')) {
                          _locationName = 'Near $_locationName';
                        }
                      }),
                    ),
                    children: [
                      osmTiles(),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _point,
                            width: 40,
                            height: 40,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _useMyLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use my location'),
                  ),
                  const Spacer(),
                  const Text(
                    'Tap map to adjust · shown ±100 m',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(
                _isFound ? 'When did you find it?' : 'When did you lose it?',
              ),
              subtitle: Text(formatDateTime(_occurredAt)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _pickDateTime,
            ),
            if (_isFound) ..._verificationSection(cat),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_submitting ? 'Processing…' : 'Submit report'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _verificationSection(ItemCategory cat) => [
    const SectionTitle('OWNERSHIP VERIFICATION (PRIVATE)'),
    const InfoBox(
      icon: Icons.lock_outline,
      text:
          'Ask about details only the real owner would know. Claimants see '
          'the questions, never the answers. Answers are stored as salted '
          'hashes. Separate acceptable alternatives with "|", e.g. "3|three".',
    ),
    for (var i = 0; i < _questions.length; i++)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Text('Question ${i + 1}'),
                  const Spacer(),
                  if (_questions.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _update(() {
                        _questions.removeAt(i).dispose();
                      }),
                    ),
                ],
              ),
              TextFormField(
                controller: _questions[i].q,
                decoration: const InputDecoration(labelText: 'Question'),
                validator: (v) =>
                    (v ?? '').trim().length < 5 ? 'Enter a question' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _questions[i].a,
                decoration: const InputDecoration(
                  labelText: 'Correct answer (hidden)',
                  prefixIcon: Icon(Icons.visibility_off_outlined),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter the answer' : null,
              ),
            ],
          ),
        ),
      ),
    if (_questions.length < AppConfig.maxVerificationQuestions)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final s in cat.suggestedQuestions)
              if (!_questions.any((q) => q.q.text == s))
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(s),
                  onPressed: () {
                    final empty = _questions.where((q) => q.q.text.isEmpty);
                    if (empty.isNotEmpty) {
                      empty.first.q.text = s;
                      setState(() {});
                    } else {
                      _addQuestion(s);
                    }
                  },
                ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Custom question'),
              onPressed: _addQuestion,
            ),
          ],
        ),
      ),
    _pad(
      TextFormField(
        controller: _notes,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Private notes (only you can see)',
          hintText: 'e.g. handed to library front desk',
        ),
      ),
    ),
  ];

  Widget _pad(Widget w) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: w);
}

/// Preview only; the uploaded JPEG is blurred in [ImageProcessing].
final _blurFilter = ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8);

class _AddPhotoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AddPhotoTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(icon), const SizedBox(height: 4), Text(label)],
        ),
      ),
    ),
  );
}
