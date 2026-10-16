import 'package:latlong2/latlong.dart';

/// Campus-specific configuration. Edit these values for your own campus.
class AppConfig {
  AppConfig._();

  static const appName = 'Finders Keepers';

  /// Centre of the campus map. Replace with your campus coordinates.
  static const campusCenter = LatLng(13.0108, 80.2354);
  static const campusZoom = 16.0;

  /// Only e-mail addresses on these domains may register (empty = allow all).
  /// Restricting sign-up to campus e-mail is the first anti-fraud layer:
  /// every claimant is a traceable member of the campus.
  static const allowedEmailDomains = <String>[];

  /// Firebase mode requires a verified campus e-mail before posting/claiming.
  static const requireEmailVerification = true;

  /// Public coordinates are snapped to a grid of this many decimal places
  /// (3 decimals ≈ 110 m) so the exact spot of an item is never published.
  static const publicLocationPrecision = 3;

  static const maxImagesPerItem = 3;
  static const maxVerificationQuestions = 3;

  /// Minimum match score (0..1) for a "possible match" alert.
  static const matchThreshold = 0.45;

  /// Named campus landmarks used for quick location selection.
  static const landmarks = <Landmark>[
    Landmark('Main Library', LatLng(13.0115, 80.2360)),
    Landmark('Central Cafeteria', LatLng(13.0100, 80.2345)),
    Landmark('Academic Block A', LatLng(13.0122, 80.2340)),
    Landmark('Academic Block B', LatLng(13.0095, 80.2365)),
    Landmark('Sports Complex', LatLng(13.0085, 80.2330)),
    Landmark('Hostel Zone', LatLng(13.0130, 80.2375)),
    Landmark('Main Gate', LatLng(13.0078, 80.2355)),
    Landmark('Auditorium', LatLng(13.0108, 80.2372)),
    Landmark('Parking Lot', LatLng(13.0090, 80.2318)),
  ];

  /// Safe, public handover point recommended to both parties.
  static const recommendedHandoverPoint = 'Campus Security Desk, Main Gate';
}

class Landmark {
  final String name;
  final LatLng position;
  const Landmark(this.name, this.position);
}
