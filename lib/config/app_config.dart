import 'package:latlong2/latlong.dart';

/// Campus-specific configuration. Edit these values for your own campus.
class AppConfig {
  AppConfig._();

  static const appName = 'Finders Keepers';

  /// VIT Vellore campus (Katpadi, Vellore, Tamil Nadu).
  static const campusName = 'VIT Vellore';
  static const campusCenter = LatLng(12.9712, 79.1600);
  static const campusZoom = 15.8;

  /// Only e-mail addresses on these domains may register (empty = allow all).
  /// Restricting sign-up to campus e-mail is the first anti-fraud layer:
  /// every claimant is a traceable member of the campus.
  static const allowedEmailDomains = <String>['vitstudent.ac.in', 'vit.ac.in'];

  /// Firebase mode requires a verified campus e-mail before posting/claiming.
  static const requireEmailVerification = true;

  /// Public coordinates are snapped to a grid of this many decimal places
  /// (3 decimals ≈ 110 m) so the exact spot of an item is never published.
  static const publicLocationPrecision = 3;

  static const maxImagesPerItem = 3;
  static const maxVerificationQuestions = 3;

  /// Minimum match score (0..1) for a "possible match" alert.
  static const matchThreshold = 0.45;

  /// Named VIT Vellore landmarks (coordinates from OpenStreetMap).
  static const landmarks = <Landmark>[
    Landmark('Main Gate', LatLng(12.96836, 79.15568)),
    Landmark('Main Building', LatLng(12.96924, 79.15589)),
    Landmark('Anna Auditorium', LatLng(12.96995, 79.15567)),
    Landmark('EV Periyar Central Library', LatLng(12.96932, 79.15686)),
    Landmark('Sir M Visvesvaraya Block (SMV)', LatLng(12.96923, 79.15773)),
    Landmark('G.D. Naidu Block (GDN)', LatLng(12.96994, 79.15484)),
    Landmark('CDMM Building', LatLng(12.96917, 79.15496)),
    Landmark('Technology Tower (TT)', LatLng(12.97066, 79.15951)),
    Landmark('Silver Jubilee Tower (SJT)', LatLng(12.97095, 79.16393)),
    Landmark('Pearl Research Park (PRP)', LatLng(12.97142, 79.16625)),
    Landmark('Food Court (near TT)', LatLng(12.97011, 79.15907)),
    Landmark('Foodys', LatLng(12.96899, 79.15834)),
    Landmark('Kalpana Chawla Ground', LatLng(12.96824, 79.15696)),
    Landmark('Outdoor Stadium', LatLng(12.97597, 79.16007)),
    Landmark("Men's Hostel (MH)", LatLng(12.97209, 79.15919)),
    Landmark("Ladies' Hostel (LH)", LatLng(12.97095, 79.16068)),
    Landmark('Health Centre', LatLng(12.96950, 79.15465)),
  ];

  /// Safe, public handover point recommended to both parties.
  static const recommendedHandoverPoint = 'VIT Main Gate security desk';
}

class Landmark {
  final String name;
  final LatLng position;
  const Landmark(this.name, this.position);
}
