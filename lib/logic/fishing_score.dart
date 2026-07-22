/// 낚시 지수 계산 (휴리스틱).
///
/// 물흐름(물때), 바람, 파고, 강수를 조합해 0~100 점수와 등급을 만든다.
/// 어종·낚시 방식에 따라 선호 물때가 다르므로 절대 기준이 아니라
/// "출조 판단 참고용" 지표다.
library;

import '../models/models.dart';
import 'multtae.dart';

class FishingIndex {
  final int score; // 0~100
  final String grade; // 아주 좋음/좋음/보통/나쁨
  final List<String> reasons; // 근거 설명

  const FishingIndex({
    required this.score,
    required this.grade,
    required this.reasons,
  });
}

FishingIndex fishingIndexFor({
  required Multae multae,
  required MarineNow now,
  required List<HourlyWeather> hourly,
}) {
  var score = 50.0;
  final reasons = <String>[];

  // 1) 물흐름: 중간~살아있는 물때(3~6물)가 무난하게 좋고, 조금·무시는 감점.
  final flow = multae.flowStrength;
  if (multae.isJogeum || multae.isMusi) {
    score -= 15;
    reasons.add('${multae.label} — 물흐름이 약한 시기예요');
  } else if (flow > 0.85) {
    score += 5;
    reasons.add('${multae.label} — 사리 부근, 물이 많이 갑니다');
  } else if (flow > 0.4) {
    score += 15;
    reasons.add('${multae.label} — 물흐름이 살아있어요');
  } else {
    score += 5;
    reasons.add('${multae.label} — 물흐름 보통');
  }

  // 2) 바람: 4m/s 이하 쾌적, 8m/s 이상 위험 수준 감점.
  final wind = now.windSpeedMs;
  if (wind != null) {
    if (wind < 4) {
      score += 15;
      reasons.add('바람 ${wind.toStringAsFixed(1)}m/s — 잔잔해요');
    } else if (wind < 8) {
      score += 0;
      reasons.add('바람 ${wind.toStringAsFixed(1)}m/s — 다소 있어요');
    } else {
      score -= 25;
      reasons.add('바람 ${wind.toStringAsFixed(1)}m/s — 강풍 주의');
    }
  }

  // 3) 파고: 0.5m 이하 좋음, 1.5m 이상 감점.
  final wave = now.waveHeightM;
  if (wave != null) {
    if (wave <= 0.5) {
      score += 15;
      reasons.add('파고 ${wave.toStringAsFixed(1)}m — 바다가 잔잔해요');
    } else if (wave <= 1.5) {
      score += 0;
      reasons.add('파고 ${wave.toStringAsFixed(1)}m — 보통');
    } else {
      score -= 25;
      reasons.add('파고 ${wave.toStringAsFixed(1)}m — 너울 주의');
    }
  }

  // 4) 강수: 앞으로 12시간 내 비 예보 감점.
  final soon = hourly.take(12);
  final rain = soon.fold<double>(
      0, (sum, h) => sum + (h.precipitationMm ?? 0));
  if (rain > 5) {
    score -= 15;
    reasons.add('12시간 내 비 예보 (${rain.toStringAsFixed(0)}mm)');
  } else if (rain > 0.5) {
    score -= 5;
    reasons.add('약한 비 소식이 있어요');
  }

  final s = score.clamp(0, 100).round();
  final grade = s >= 75
      ? '아주 좋음'
      : s >= 55
          ? '좋음'
          : s >= 35
              ? '보통'
              : '나쁨';

  return FishingIndex(score: s, grade: grade, reasons: reasons);
}
