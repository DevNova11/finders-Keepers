import 'package:flutter/material.dart';

/// Converts Firestore Timestamps, ISO strings, epoch ints or DateTimes.
DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  try {
    return (v as dynamic).toDate() as DateTime; // Firestore Timestamp
  } catch (_) {
    return null;
  }
}

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

enum ItemType { lost, found }

/// Lifecycle of an item:
///   lost  ──(owner's claim approved)──▶ claimed ──▶ returned
///   found ──(finder approves claim)──▶ claimed ──(handover code)──▶ returned
/// Either can be `closed` by its reporter (withdrawn / handed to security).
enum ItemStatus { lost, found, claimed, returned, closed }

enum ClaimStatus { pending, approved, rejected, withdrawn, completed }

T _enumByName<T extends Enum>(List<T> values, dynamic name, T fallback) =>
    values.firstWhere((e) => e.name == name, orElse: () => fallback);

extension ItemStatusX on ItemStatus {
  String get label => switch (this) {
    ItemStatus.lost => 'Lost',
    ItemStatus.found => 'Found',
    ItemStatus.claimed => 'Claimed',
    ItemStatus.returned => 'Returned',
    ItemStatus.closed => 'Closed',
  };
  Color get color => switch (this) {
    ItemStatus.lost => const Color(0xFFD9534F),
    ItemStatus.found => const Color(0xFF2E7D32),
    ItemStatus.claimed => const Color(0xFFEF8F00),
    ItemStatus.returned => const Color(0xFF1565C0),
    ItemStatus.closed => const Color(0xFF757575),
  };
  bool get isOpen => this == ItemStatus.lost || this == ItemStatus.found;
}

extension ClaimStatusX on ClaimStatus {
  String get label => switch (this) {
    ClaimStatus.pending => 'Under review',
    ClaimStatus.approved => 'Approved – awaiting handover',
    ClaimStatus.rejected => 'Rejected',
    ClaimStatus.withdrawn => 'Withdrawn',
    ClaimStatus.completed => 'Completed – item returned',
  };
  Color get color => switch (this) {
    ClaimStatus.pending => const Color(0xFFEF8F00),
    ClaimStatus.approved => const Color(0xFF2E7D32),
    ClaimStatus.rejected => const Color(0xFFD9534F),
    ClaimStatus.withdrawn => const Color(0xFF757575),
    ClaimStatus.completed => const Color(0xFF1565C0),
  };
}

class ItemCategory {
  final String id;
  final String label;
  final IconData icon;

  /// Photos in sensitive categories are blurred by default.
  final bool sensitive;

  /// Suggested private verification questions for finders.
  final List<String> suggestedQuestions;

  const ItemCategory(
    this.id,
    this.label,
    this.icon, {
    this.sensitive = false,
    this.suggestedQuestions = const [],
  });

  static const all = <ItemCategory>[
    ItemCategory(
      'id_card',
      'ID card / documents',
      Icons.badge_outlined,
      sensitive: true,
      suggestedQuestions: [
        'What name is printed on the card?',
        'What is your department or course?',
        'What are the last 4 digits of the ID number?',
      ],
    ),
    ItemCategory(
      'wallet',
      'Wallet / purse',
      Icons.account_balance_wallet_outlined,
      sensitive: true,
      suggestedQuestions: [
        'What brand is the wallet?',
        'Name one item (not cash) that is inside it.',
        'What colour is the inside lining?',
      ],
    ),
    ItemCategory(
      'keys',
      'Keys',
      Icons.key_outlined,
      suggestedQuestions: [
        'How many keys are on the ring?',
        'Describe the keychain attached to it.',
      ],
    ),
    ItemCategory(
      'earphones',
      'Earphones / headphones',
      Icons.headphones_outlined,
      suggestedQuestions: [
        'What brand and model are they?',
        'Describe any case, sticker or scratch.',
      ],
    ),
    ItemCategory(
      'phone',
      'Phone',
      Icons.smartphone_outlined,
      sensitive: true,
      suggestedQuestions: [
        'What is the lock-screen wallpaper?',
        'Describe the phone case.',
        'What brand and model is it?',
      ],
    ),
    ItemCategory(
      'laptop',
      'Laptop / tablet',
      Icons.laptop_outlined,
      sensitive: true,
      suggestedQuestions: [
        'What brand and model is it?',
        'Describe any stickers on the lid.',
        'What is the device/login name shown at start-up?',
      ],
    ),
    ItemCategory(
      'bag',
      'Bag / backpack',
      Icons.backpack_outlined,
      suggestedQuestions: [
        'What brand is the bag?',
        'Name one item inside the main pocket.',
      ],
    ),
    ItemCategory(
      'bottle',
      'Water bottle',
      Icons.local_drink_outlined,
      suggestedQuestions: ['Describe any stickers or marks on the bottle.'],
    ),
    ItemCategory(
      'books',
      'Books / stationery',
      Icons.menu_book_outlined,
      suggestedQuestions: ['What is written on the first page?'],
    ),
    ItemCategory(
      'clothing',
      'Clothing / accessories',
      Icons.checkroom_outlined,
      suggestedQuestions: ['What size/brand label does it have?'],
    ),
    ItemCategory(
      'other',
      'Other',
      Icons.category_outlined,
      suggestedQuestions: ['Describe a detail not visible in the photos.'],
    ),
  ];

  static ItemCategory byId(String? id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.last);
}

class StatusEvent {
  final ItemStatus status;
  final DateTime at;
  final String note;

  const StatusEvent(this.status, this.at, this.note);

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'at': at,
    'note': note,
  };

  factory StatusEvent.fromMap(Map<String, dynamic> m) => StatusEvent(
    _enumByName(ItemStatus.values, m['status'], ItemStatus.lost),
    parseDate(m['at']) ?? DateTime.now(),
    (m['note'] ?? '') as String,
  );
}

/// Public item document: `items/{itemId}`. Contains nothing identifying
/// about the reporter beyond an alias, and only an approximate location.
class Item {
  final String id;
  final ItemType type;
  final String title;
  final String description;
  final String category;
  final String color;
  final ItemStatus status;
  final String locationName;
  final double lat; // approximate (grid-snapped)
  final double lng;
  final DateTime occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String reporterId;
  final String reporterAlias;
  final List<String> imageUrls;
  final List<String> imageHashes; // 64-bit dHash hex per image
  final List<String> keywords;
  final List<String> verificationQuestions; // questions only, never answers
  final String? linkedItemId; // a found report answering a lost report
  final String? approvedClaimId;
  final List<StatusEvent> history;

  /// Set by a moderator: the post is removed from listings and the map.
  final bool hidden;
  final String? moderationNote;

  const Item({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.category,
    required this.color,
    required this.status,
    required this.locationName,
    required this.lat,
    required this.lng,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    required this.reporterId,
    required this.reporterAlias,
    this.imageUrls = const [],
    this.imageHashes = const [],
    this.keywords = const [],
    this.verificationQuestions = const [],
    this.linkedItemId,
    this.approvedClaimId,
    this.history = const [],
    this.hidden = false,
    this.moderationNote,
  });

  ItemCategory get categoryInfo => ItemCategory.byId(category);
  bool get isFound => type == ItemType.found;

  Item copyWith({
    ItemStatus? status,
    List<String>? imageUrls,
    String? approvedClaimId,
    DateTime? updatedAt,
    List<StatusEvent>? history,
    bool? hidden,
    String? moderationNote,
  }) => Item(
    id: id,
    type: type,
    title: title,
    description: description,
    category: category,
    color: color,
    status: status ?? this.status,
    locationName: locationName,
    lat: lat,
    lng: lng,
    occurredAt: occurredAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    reporterId: reporterId,
    reporterAlias: reporterAlias,
    imageUrls: imageUrls ?? this.imageUrls,
    imageHashes: imageHashes,
    keywords: keywords,
    verificationQuestions: verificationQuestions,
    linkedItemId: linkedItemId,
    approvedClaimId: approvedClaimId ?? this.approvedClaimId,
    history: history ?? this.history,
    hidden: hidden ?? this.hidden,
    moderationNote: moderationNote ?? this.moderationNote,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'title': title,
    'description': description,
    'category': category,
    'color': color,
    'status': status.name,
    'locationName': locationName,
    'lat': lat,
    'lng': lng,
    'occurredAt': occurredAt,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'reporterId': reporterId,
    'reporterAlias': reporterAlias,
    'imageUrls': imageUrls,
    'imageHashes': imageHashes,
    'keywords': keywords,
    'verificationQuestions': verificationQuestions,
    'linkedItemId': linkedItemId,
    'approvedClaimId': approvedClaimId,
    'history': history.map((e) => e.toMap()).toList(),
    'hidden': hidden,
    'moderationNote': moderationNote,
  };

  factory Item.fromMap(Map<String, dynamic> m) => Item(
    id: m['id'] as String,
    type: _enumByName(ItemType.values, m['type'], ItemType.lost),
    title: (m['title'] ?? '') as String,
    description: (m['description'] ?? '') as String,
    category: (m['category'] ?? 'other') as String,
    color: (m['color'] ?? '') as String,
    status: _enumByName(ItemStatus.values, m['status'], ItemStatus.lost),
    locationName: (m['locationName'] ?? '') as String,
    lat: (m['lat'] as num?)?.toDouble() ?? 0,
    lng: (m['lng'] as num?)?.toDouble() ?? 0,
    occurredAt: parseDate(m['occurredAt']) ?? DateTime.now(),
    createdAt: parseDate(m['createdAt']) ?? DateTime.now(),
    updatedAt: parseDate(m['updatedAt']) ?? DateTime.now(),
    reporterId: (m['reporterId'] ?? '') as String,
    reporterAlias: (m['reporterAlias'] ?? 'Anonymous') as String,
    imageUrls: _strings(m['imageUrls']),
    imageHashes: _strings(m['imageHashes']),
    keywords: _strings(m['keywords']),
    verificationQuestions: _strings(m['verificationQuestions']),
    linkedItemId: m['linkedItemId'] as String?,
    approvedClaimId: m['approvedClaimId'] as String?,
    history: (m['history'] as List? ?? [])
        .map((e) => StatusEvent.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    hidden: m['hidden'] == true,
    moderationNote: m['moderationNote'] as String?,
  );
}

/// Private document readable only by the reporter:
/// `items/{itemId}/private/secret`.
class ItemSecret {
  /// question index → salted SHA-256 hashes of acceptable answers.
  final Map<String, List<String>> answerHashes;
  final String salt;
  final double? exactLat;
  final double? exactLng;
  final String privateNotes;

  const ItemSecret({
    required this.answerHashes,
    required this.salt,
    this.exactLat,
    this.exactLng,
    this.privateNotes = '',
  });

  Map<String, dynamic> toMap() => {
    'answerHashes': answerHashes,
    'salt': salt,
    'exactLat': exactLat,
    'exactLng': exactLng,
    'privateNotes': privateNotes,
  };

  factory ItemSecret.fromMap(Map<String, dynamic> m) => ItemSecret(
    answerHashes: (m['answerHashes'] as Map? ?? {}).map(
      (k, v) => MapEntry(k.toString(), _strings(v)),
    ),
    salt: (m['salt'] ?? '') as String,
    exactLat: (m['exactLat'] as num?)?.toDouble(),
    exactLng: (m['exactLng'] as num?)?.toDouble(),
    privateNotes: (m['privateNotes'] ?? '') as String,
  );
}

/// Ownership claim: `claims/{itemId}_{claimantId}` — one attempt per user
/// per item, readable only by the claimant and the item's reporter.
class Claim {
  final String id;
  final String itemId;
  final String itemTitle;
  final String itemReporterId;
  final String claimantId;
  final String claimantAlias;
  final List<String> answers;
  final String description;
  final String? proofImageUrl;
  final String? claimantLostItemId;
  final ClaimStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? rejectionReason;
  final String? handoverCodeHash;
  final String? handoverSalt;

  /// Set server-side (Cloud Function) when the claimant shows suspicious
  /// behaviour, e.g. many claims in a short time.
  final String? flagReason;

  const Claim({
    required this.id,
    required this.itemId,
    required this.itemTitle,
    required this.itemReporterId,
    required this.claimantId,
    required this.claimantAlias,
    required this.answers,
    required this.description,
    this.proofImageUrl,
    this.claimantLostItemId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.rejectionReason,
    this.handoverCodeHash,
    this.handoverSalt,
    this.flagReason,
  });

  static String idFor(String itemId, String uid) => '${itemId}_$uid';

  bool get isActive =>
      status == ClaimStatus.pending || status == ClaimStatus.approved;

  Map<String, dynamic> toMap() => {
    'id': id,
    'itemId': itemId,
    'itemTitle': itemTitle,
    'itemReporterId': itemReporterId,
    'claimantId': claimantId,
    'claimantAlias': claimantAlias,
    'answers': answers,
    'description': description,
    'proofImageUrl': proofImageUrl,
    'claimantLostItemId': claimantLostItemId,
    'status': status.name,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'rejectionReason': rejectionReason,
    'handoverCodeHash': handoverCodeHash,
    'handoverSalt': handoverSalt,
    'flagReason': flagReason,
  };

  factory Claim.fromMap(Map<String, dynamic> m) => Claim(
    id: m['id'] as String,
    itemId: (m['itemId'] ?? '') as String,
    itemTitle: (m['itemTitle'] ?? '') as String,
    itemReporterId: (m['itemReporterId'] ?? '') as String,
    claimantId: (m['claimantId'] ?? '') as String,
    claimantAlias: (m['claimantAlias'] ?? 'Anonymous') as String,
    answers: _strings(m['answers']),
    description: (m['description'] ?? '') as String,
    proofImageUrl: m['proofImageUrl'] as String?,
    claimantLostItemId: m['claimantLostItemId'] as String?,
    status: _enumByName(ClaimStatus.values, m['status'], ClaimStatus.pending),
    createdAt: parseDate(m['createdAt']) ?? DateTime.now(),
    updatedAt: parseDate(m['updatedAt']) ?? DateTime.now(),
    rejectionReason: m['rejectionReason'] as String?,
    handoverCodeHash: m['handoverCodeHash'] as String?,
    handoverSalt: m['handoverSalt'] as String?,
    flagReason: m['flagReason'] as String?,
  );
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderAlias;
  final String text;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderAlias,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'senderId': senderId,
    'senderAlias': senderAlias,
    'text': text,
    'createdAt': createdAt,
  };

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
    id: m['id'] as String,
    senderId: (m['senderId'] ?? '') as String,
    senderAlias: (m['senderAlias'] ?? '') as String,
    text: (m['text'] ?? '') as String,
    createdAt: parseDate(m['createdAt']) ?? DateTime.now(),
  );
}

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final bool emailVerified;

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.emailVerified,
  });

  /// Public alias: first name + last initial ("Asha R."). E-mail and full
  /// name are never shown to other users.
  String get alias {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'Student';
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last[0].toUpperCase()}.';
  }
}

enum ReportStatus { open, dismissed, actioned }

/// Abuse report on a post: `reports/{id}`. Created by any verified user,
/// readable and resolvable only by moderators (`admins/{uid}`).
class AbuseReport {
  final String id;
  final String itemId;
  final String itemTitle;
  final String itemReporterId;
  final String itemReporterAlias;
  final String reporterId;
  final String reason;
  final ReportStatus status;
  final String? resolution;
  final DateTime createdAt;

  const AbuseReport({
    required this.id,
    required this.itemId,
    required this.itemTitle,
    required this.itemReporterId,
    required this.itemReporterAlias,
    required this.reporterId,
    required this.reason,
    required this.status,
    this.resolution,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'itemId': itemId,
    'itemTitle': itemTitle,
    'itemReporterId': itemReporterId,
    'itemReporterAlias': itemReporterAlias,
    'reporterId': reporterId,
    'reason': reason,
    'status': status.name,
    'resolution': resolution,
    'createdAt': createdAt,
  };

  factory AbuseReport.fromMap(Map<String, dynamic> m) => AbuseReport(
    id: m['id'] as String,
    itemId: (m['itemId'] ?? '') as String,
    itemTitle: (m['itemTitle'] ?? '') as String,
    itemReporterId: (m['itemReporterId'] ?? '') as String,
    itemReporterAlias: (m['itemReporterAlias'] ?? '') as String,
    reporterId: (m['reporterId'] ?? '') as String,
    reason: (m['reason'] ?? '') as String,
    status: _enumByName(ReportStatus.values, m['status'], ReportStatus.open),
    resolution: m['resolution'] as String?,
    createdAt: parseDate(m['createdAt']) ?? DateTime.now(),
  );
}
