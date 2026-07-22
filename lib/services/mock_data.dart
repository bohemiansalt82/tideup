/// 목업 데이터 생성기 — API 키가 없을 때 실제와 같은 형태의 샘플 제공.
///
/// 조석은 M2 분조(주기 약 12시간 25분)를 닮은 사인 곡선으로 만들고,
/// 진폭은 물때(월령)에 따라 커졌다 작아졌다 하게 한다.
library;

import 'dart:math' as math;

import '../logic/sun_moon.dart';
import '../models/models.dart';

class MockDataSource {
  /// 특정 날짜의 만조/간조만 (주간 물때 달력용).
  List<TideEvent> eventsFor(Station station, DateTime date) =>
      generate(station, date).tideEvents;

  /// 지점 좌표를 시드로 써서 지점마다 다른 곡선을 만든다.
  StationDayData generate(Station station, DateTime date) {
    final seed = (station.lat * 7 + station.lon * 13);
    final phaseShift = (seed % 12.42) * 3600; // 지점별 위상차 (초)

    // 월령 기반 진폭: 사리(보름/그믐) 부근 최대
    final age = moonAge(date);
    final syzygyDist = math.min(
      math.min((age - 0).abs(), (age - 29.53).abs()),
      (age - 14.77).abs(),
    ); // 0 = 사리
    final springFactor = 1.0 - (syzygyDist / 7.4).clamp(0.0, 1.0) * 0.55;
    final amplitude = 250.0 * springFactor; // cm
    const mean = 450.0; // 평균 해면 (cm)

    const m2Period = 12.4206 * 3600; // 초

    double levelAt(DateTime t) {
      final sec =
          t.difference(DateTime(2000, 1, 1)).inSeconds.toDouble() + phaseShift;
      final main = amplitude * math.sin(2 * math.pi * sec / m2Period);
      final diurnal = amplitude * 0.18 * math.sin(2 * math.pi * sec / (23.93 * 3600));
      return mean + main + diurnal;
    }

    // 곡선: 오늘 0시~내일 0시, 10분 간격
    final dayStart = DateTime(date.year, date.month, date.day);
    final curve = <TidePoint>[];
    for (var m = 0; m <= 24 * 60; m += 10) {
      final t = dayStart.add(Duration(minutes: m));
      curve.add(TidePoint(t, levelAt(t)));
    }

    // 만조/간조: 곡선에서 극값 탐색 (오늘~내일)
    final events = <TideEvent>[];
    TidePoint? prev, prev2;
    for (var m = -30; m <= 48 * 60; m += 6) {
      final t = dayStart.add(Duration(minutes: m));
      final p = TidePoint(t, levelAt(t));
      if (prev != null && prev2 != null) {
        if (prev.levelCm > prev2.levelCm && prev.levelCm > p.levelCm) {
          events.add(TideEvent(
              time: prev.time, levelCm: prev.levelCm, type: TideEventType.high));
        } else if (prev.levelCm < prev2.levelCm && prev.levelCm < p.levelCm) {
          events.add(TideEvent(
              time: prev.time, levelCm: prev.levelCm, type: TideEventType.low));
        }
      }
      prev2 = prev;
      prev = p;
    }

    // 시간별 날씨: 그럴듯한 여름 해안 날씨
    final rng = math.Random(seed.toInt() + date.day);
    final hourly = <HourlyWeather>[];
    for (var h = 0; h < 48; h++) {
      final t = dayStart.add(Duration(hours: h));
      final hourOfDay = t.hour;
      final temp = 23 +
          4 * math.sin((hourOfDay - 6) / 24 * 2 * math.pi) +
          rng.nextDouble();
      hourly.add(HourlyWeather(
        time: t,
        tempC: temp,
        windSpeedMs: 2.5 + 2 * rng.nextDouble() + (hourOfDay > 12 ? 1.5 : 0),
        windDirDeg: 180 + 60 * math.sin(h / 8),
        waveHeightM: 0.3 + 0.4 * rng.nextDouble(),
        waterTempC: 21 +
            (seed % 5) +
            0.6 * math.sin((hourOfDay - 8) / 24 * 2 * math.pi),
        weatherCode: hourOfDay > 15 && rng.nextDouble() > 0.8 ? 2 : 0,
        precipitationMm: 0,
      ));
    }

    final nowHour = hourly.firstWhere(
      (h) => h.time.isAfter(DateTime.now().subtract(const Duration(hours: 1))),
      orElse: () => hourly.first,
    );

    return StationDayData(
      station: station,
      tideEvents: events,
      tideCurve: curve,
      hourly: hourly,
      fetchedAt: DateTime.now(),
      now: MarineNow(
        waterTempC: 21 + (seed % 5),
        airTempC: nowHour.tempC,
        windSpeedMs: nowHour.windSpeedMs,
        windDirDeg: nowHour.windDirDeg,
        waveHeightM: nowHour.waveHeightM,
      ),
      isMock: true,
    );
  }
}
