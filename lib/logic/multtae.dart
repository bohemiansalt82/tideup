/// 물때(물흐름) 계산.
///
/// 물때는 음력 날짜로 정해지며 지역에 따라 세는 방식이 다르다:
/// - 7물때식(서해·남해 서부): 음력 1일 = 7물, 8일 = 조금, 9일 = 무시, 10일 = 1물
/// - 8물때식(남해 동부·동해): 무시가 없고 조금 다음날 바로 1물, 음력 1일 = 8물
library;

import 'package:klc/klc.dart';

enum MultaeSystem { west7, south8 }

class Multae {
  final String label; // 예: "7물", "조금", "무시"
  final int? mul; // 물 수 (조금/무시는 null)
  final int lunarDay;
  final int lunarMonth;
  final MultaeSystem system;

  const Multae({
    required this.label,
    required this.mul,
    required this.lunarDay,
    required this.lunarMonth,
    required this.system,
  });

  bool get isJogeum => label == '조금';
  bool get isMusi => label == '무시';

  /// 다음 사리(음력 15/30 부근)까지 남은 날 (0이면 오늘).
  int get daysToSari => _daysTo(const [15, 30]);

  /// 다음 조금(음력 8/23)까지 남은 날 (0이면 오늘).
  int get daysToJogeum => _daysTo(const [8, 23]);

  int _daysTo(List<int> targets) {
    var best = 30;
    for (final t in targets) {
      final d = (t - lunarDay) % 30;
      if (d < best) best = d;
    }
    return best;
  }

  /// 물흐름 세기 0.0(거의 없음)~1.0(최대). 사리(대조) 부근이 1.0.
  ///
  /// 조금·무시 부근이 소조(물이 죽는 시기), 사리(음력 보름/그믐 근처)가
  /// 대조(물이 가장 살아있는 시기)이다.
  double get flowStrength {
    // 음력일 기준 보름(15)/그믐(30)과의 거리로 계산 (사리 = 보름·그믐 +1~2일)
    final d = lunarDay;
    final distFull = (d - 16).abs();
    final distNew = (d - 1).abs() < (d - 31).abs() ? (d - 1).abs() : (d - 31).abs();
    final dist = distFull < distNew ? distFull : distNew; // 0~7
    return (1.0 - (dist / 7.5)).clamp(0.0, 1.0);
  }
}

// 7물때식: 음력일(1~30) → 표기
const List<String> _west7Table = [
  '7물', '8물', '9물', '10물', '11물', '12물', '13물', '조금', '무시',
  '1물', '2물', '3물', '4물', '5물', '6물',
  '7물', '8물', '9물', '10물', '11물', '12물', '13물', '조금', '무시',
  '1물', '2물', '3물', '4물', '5물', '6물',
];

// 8물때식: 음력일(1~30) → 표기 (무시 없음)
const List<String> _south8Table = [
  '8물', '9물', '10물', '11물', '12물', '13물', '14물', '조금',
  '1물', '2물', '3물', '4물', '5물', '6물', '7물',
  '8물', '9물', '10물', '11물', '12물', '13물', '14물', '조금',
  '1물', '2물', '3물', '4물', '5물', '6물', '7물',
];

/// 경도 기준 물때식 자동 선택.
///
/// 서해안·남해 서부(전남권, 대략 동경 127.5° 이서)는 7물때식,
/// 남해 동부(경남·부산)·동해는 8물때식을 주로 쓴다.
MultaeSystem systemForLocation(double lat, double lon) {
  return lon < 127.5 ? MultaeSystem.west7 : MultaeSystem.south8;
}

/// 주어진 양력 날짜의 물때를 구한다.
Multae multaeFor(DateTime date, MultaeSystem system) {
  setSolarDate(date.year, date.month, date.day);
  final lunarMonth = getLunarMonth();
  final lunarDay = getLunarDay();

  final table = system == MultaeSystem.west7 ? _west7Table : _south8Table;
  final label = table[(lunarDay - 1).clamp(0, 29)];
  final mul = label.endsWith('물') && !label.startsWith('무')
      ? int.tryParse(label.replaceAll('물', ''))
      : null;

  return Multae(
    label: label,
    mul: mul,
    lunarDay: lunarDay,
    lunarMonth: lunarMonth,
    system: system,
  );
}
