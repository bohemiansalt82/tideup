/// 일출·일몰(NOAA 근사식)과 월령 계산.
library;

import 'dart:math' as math;

class SunTimes {
  final DateTime? sunrise;
  final DateTime? sunset;

  const SunTimes({this.sunrise, this.sunset});
}

double _deg2rad(double d) => d * math.pi / 180.0;
double _rad2deg(double r) => r * 180.0 / math.pi;

/// NOAA 태양 위치 근사식으로 일출/일몰 시각(로컬 시간)을 구한다.
SunTimes sunTimesFor(DateTime date, double lat, double lon) {
  DateTime? calc(bool isSunrise) {
    final n = DateTime(date.year, date.month, date.day)
            .difference(DateTime(date.year, 1, 1))
            .inDays +
        1;
    final lngHour = lon / 15.0;
    final t = isSunrise ? n + ((6 - lngHour) / 24) : n + ((18 - lngHour) / 24);

    final m = (0.9856 * t) - 3.289; // 태양 평균 근점 이각
    var l = m +
        (1.916 * math.sin(_deg2rad(m))) +
        (0.020 * math.sin(_deg2rad(2 * m))) +
        282.634;
    l = l % 360.0;

    var ra = _rad2deg(math.atan(0.91764 * math.tan(_deg2rad(l))));
    ra = ra % 360.0;
    final lQuadrant = (l / 90).floor() * 90.0;
    final raQuadrant = (ra / 90).floor() * 90.0;
    ra = ra + (lQuadrant - raQuadrant);
    ra = ra / 15.0;

    final sinDec = 0.39782 * math.sin(_deg2rad(l));
    final cosDec = math.cos(math.asin(sinDec));

    const zenith = 90.833; // 공식 일출몰 천정각
    final cosH = (math.cos(_deg2rad(zenith)) -
            (sinDec * math.sin(_deg2rad(lat)))) /
        (cosDec * math.cos(_deg2rad(lat)));
    if (cosH > 1 || cosH < -1) return null; // 백야/극야

    var h = isSunrise
        ? 360 - _rad2deg(math.acos(cosH))
        : _rad2deg(math.acos(cosH));
    h = h / 15.0;

    final localMeanTime = h + ra - (0.06571 * t) - 6.622;
    var utcTime = (localMeanTime - lngHour) % 24.0;
    if (utcTime < 0) utcTime += 24.0;

    final utc = DateTime.utc(date.year, date.month, date.day)
        .add(Duration(milliseconds: (utcTime * 3600 * 1000).round()));
    final local = utc.toLocal();
    // UT 기준이라 로컬 날짜가 하루 어긋날 수 있다 — 요청한 날짜로 정규화.
    return DateTime(
        date.year, date.month, date.day, local.hour, local.minute);
  }

  return SunTimes(sunrise: calc(true), sunset: calc(false));
}

/// 월령 (0.0 = 삭/그믐, ~14.77 = 보름, 주기 29.53일).
double moonAge(DateTime date) {
  // 기준 삭(신월): 2000-01-06 18:14 UTC
  final ref = DateTime.utc(2000, 1, 6, 18, 14);
  const synodic = 29.530588853;
  final days = date.toUtc().difference(ref).inMinutes / (60 * 24);
  var age = days % synodic;
  if (age < 0) age += synodic;
  return age;
}

/// 월령 → 위상 이름.
String moonPhaseName(double age) {
  if (age < 1.85) return '삭 (그믐달)';
  if (age < 5.54) return '초승달';
  if (age < 9.23) return '상현달';
  if (age < 12.92) return '차오르는 달';
  if (age < 16.61) return '보름달';
  if (age < 20.30) return '기우는 달';
  if (age < 23.99) return '하현달';
  if (age < 27.68) return '그믐달';
  return '삭 (그믐달)';
}

/// 월령 → 이모지 아이콘.
String moonPhaseEmoji(double age) {
  if (age < 1.85) return '🌑';
  if (age < 5.54) return '🌒';
  if (age < 9.23) return '🌓';
  if (age < 12.92) return '🌔';
  if (age < 16.61) return '🌕';
  if (age < 20.30) return '🌖';
  if (age < 23.99) return '🌗';
  if (age < 27.68) return '🌘';
  return '🌑';
}
