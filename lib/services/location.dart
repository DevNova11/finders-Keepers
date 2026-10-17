import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

enum LocationStatus { unknown, loading, denied, onCampus, offCampus }

class UserLocation {
  final LocationStatus status;

  /// Point used for recommendations: the real position on campus, or the
  /// campus centre when the user is away (or for testing on an emulator).
  final LatLng? point;
  const UserLocation(this.status, [this.point]);

  bool get available => point != null;
}

/// Students further than this from the campus centre are treated as
/// off campus, and recommendations fall back to the campus centre.
const offCampusMetres = 3000.0;

final userLocationProvider =
    NotifierProvider<UserLocationNotifier, UserLocation>(
      UserLocationNotifier.new,
    );

/// Location is only read on the device and never uploaded.
class UserLocationNotifier extends Notifier<UserLocation> {
  @override
  UserLocation build() {
    // If permission was granted before, load silently; never prompt here.
    Future.microtask(() async {
      final p = await Geolocator.checkPermission();
      if (p == LocationPermission.always ||
          p == LocationPermission.whileInUse) {
        await refresh();
      }
    });
    return const UserLocation(LocationStatus.unknown);
  }

  /// Asks for permission if needed, then reads the current position.
  Future<void> request() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      state = const UserLocation(LocationStatus.denied);
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    state = UserLocation(LocationStatus.loading, state.point);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final here = LatLng(pos.latitude, pos.longitude);
      final away = const Distance().as(
        LengthUnit.Meter,
        here,
        AppConfig.campusCenter,
      );
      state = away > offCampusMetres
          ? const UserLocation(LocationStatus.offCampus, AppConfig.campusCenter)
          : UserLocation(LocationStatus.onCampus, here);
    } catch (_) {
      state = const UserLocation(LocationStatus.denied);
    }
  }
}
