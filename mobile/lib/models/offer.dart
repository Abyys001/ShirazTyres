import 'job.dart';
import 'json.dart';

/// One dispatch offer (specification 6). In selection mode a driver can hold
/// several at once; in automatic mode there is exactly one and it is already
/// assigned to them until they reject it.
class Offer {
  const Offer({
    required this.id,
    required this.rank,
    required this.etaMinutes,
    required this.distanceMetres,
    required this.state,
    required this.mode,
    required this.offeredAt,
    required this.expiresAt,
    required this.job,
  });

  factory Offer.fromJson(Map<String, dynamic> json) {
    final offer = asMap(json['offer'] ?? json);
    return Offer(
      id: asInt(offer['id']),
      rank: asInt(offer['rank']),
      etaMinutes: offer['eta_minutes'] == null ? null : asInt(offer['eta_minutes']),
      distanceMetres: offer['distance_metres'] == null ? null : asInt(offer['distance_metres']),
      state: asString(offer['state']),
      mode: asString(offer['mode']),
      offeredAt: asDate(offer['offered_at']),
      expiresAt: asDate(offer['expires_at']),
      job: json['job'] == null ? null : Job.fromJson(asMap(json['job'])),
    );
  }

  final int id;
  final int rank;
  final int? etaMinutes;
  final int? distanceMetres;
  final String state;
  final String mode;
  final DateTime? offeredAt;
  final DateTime? expiresAt;
  final Job? job;

  bool get isLive => state == 'offered';

  /// How long the driver has left to answer, for the countdown on the offer card.
  Duration get remaining {
    if (expiresAt == null) return Duration.zero;
    final left = expiresAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// The whole window the office allowed, so the card can draw [remaining] as a
  /// fraction rather than as a bare number counting down out of nowhere.
  Duration get total {
    if (offeredAt == null || expiresAt == null) return Duration.zero;
    final window = expiresAt!.difference(offeredAt!);
    return window.isNegative ? Duration.zero : window;
  }
}
