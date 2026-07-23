/// TideBED 예측 조위 API (공공데이터포털, data.go.kr).
///
/// 좌표(위경도)만으로 예측 조위 시계열을 준다 — 관측소 코드 불필요.
/// End Point: apis.data.go.kr/1192136/tidebed/GetTidebedApiService
/// 파라미터: serviceKey, type=json, lat, lot, reqDate=YYYYMMDD, min(간격)
///   ⚠️ lat/lot은 소수점 2자리까지만 허용된다 (3자리 이상이면 INVALID).
/// 응답 item: obsvtrNm(기준항 이름), obsrvnDt(시각 "yyyy-MM-dd HH:mm"),
///   obsrvnHgt(예측 조위 cm).
///
/// 만조/간조는 이 곡선의 극값에서 도출한다 (TideBED는 곡선만 제공).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class TideBedException implements Exception {
  final String message;
  TideBedException(this.message);
  @override
  String toString() => 'TideBedException: $message';
}

/// TideBED 하루치 결과.
class TideBedDay {
  final String refName; // 기준항 이름 (예: 인천)
  final List<TidePoint> curve;
  final List<TideEvent> events;

  const TideBedDay(
      {required this.refName, required this.curve, required this.events});
}

class TideBedApi {
  static const _base =
      'https://apis.data.go.kr/1192136/tidebed/GetTidebedApiService';
  final String serviceKey;
  final http.Client _client;

  TideBedApi(this.serviceKey, {http.Client? client})
      : _client = client ?? http.Client();

  static String _fmtDate(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  /// 하루치 예측 조위 곡선 + 도출한 만조/간조.
  ///
  /// 좌표를 2자리로 반올림하면 육지로 이동해 INVALID가 날 수 있어,
  /// [fallbackLat]/[fallbackLon](보통 최근접 관측소 좌표)이 주어지면
  /// 실패 시 한 번 더 시도한다.
  Future<TideBedDay> fetchDay(double lat, double lon, DateTime date,
      {int min = 10, double? fallbackLat, double? fallbackLon}) async {
    // 시도할 좌표 목록: 지점 좌표 → (다르면) 최근접 관측소 좌표
    final coords = <(double, double)>[(lat, lon)];
    if (fallbackLat != null &&
        fallbackLon != null &&
        (fallbackLat.toStringAsFixed(2) != lat.toStringAsFixed(2) ||
            fallbackLon.toStringAsFixed(2) != lon.toStringAsFixed(2))) {
      coords.add((fallbackLat, fallbackLon));
    }

    TideBedException? lastErr;
    for (final (clat, clon) in coords) {
      // 일시적 실패(rate limit·네트워크)는 backoff 재시도.
      // 파라미터 무효(동해 등 미지원)는 재시도 무의미 → 다음 좌표로.
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          return await _fetchRaw(clat, clon, date, min);
        } on TideBedException catch (e) {
          lastErr = e;
          if (e.message.contains('INVALID')) break;
          if (attempt < 2) {
            await Future.delayed(
                Duration(milliseconds: 500 * (attempt + 1)));
          }
        }
      }
    }
    throw lastErr ?? TideBedException('unknown');
  }

  Future<TideBedDay> _fetchRaw(
      double lat, double lon, DateTime date, int min) async {
    // 좌표는 소수점 2자리까지만 허용
    final uri = Uri.parse(_base).replace(queryParameters: {
      'serviceKey': serviceKey,
      'type': 'json',
      'lat': lat.toStringAsFixed(2),
      'lot': lon.toStringAsFixed(2),
      'reqDate': _fmtDate(date),
      'min': '$min',
      'numOfRows': '300',
      'pageNo': '1',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw TideBedException('HTTP ${res.statusCode}');
    }
    final body = res.body.trim();
    if (!body.startsWith('{')) {
      throw TideBedException('비정상 응답 — 인증키/활용신청을 확인하세요');
    }
    final j = json.decode(body) as Map<String, dynamic>;
    final code = (j['header'] as Map?)?['resultCode'];
    if (code != '00') {
      throw TideBedException(
          '${(j['header'] as Map?)?['resultMsg'] ?? code}');
    }
    final items =
        ((j['body'] as Map?)?['items'] as Map?)?['item'] as List? ?? const [];
    String refName = '';
    final curve = <TidePoint>[];
    for (final row in items.cast<Map<String, dynamic>>()) {
      refName = row['obsvtrNm']?.toString() ?? refName;
      final t = DateTime.tryParse(
          (row['obsrvnDt']?.toString() ?? '').replaceFirst(' ', 'T'));
      final h = (row['obsrvnHgt'] as num?)?.toDouble();
      if (t == null || h == null) continue;
      curve.add(TidePoint(t, h));
    }
    curve.sort((a, b) => a.time.compareTo(b.time));
    return TideBedDay(
      refName: refName,
      curve: curve,
      events: _extractEvents(curve),
    );
  }

  /// 조위 곡선의 극값 → 만조/간조 이벤트.
  static List<TideEvent> _extractEvents(List<TidePoint> curve) {
    final events = <TideEvent>[];
    if (curve.length < 3) return events;
    for (var i = 1; i < curve.length - 1; i++) {
      final prev = curve[i - 1].levelCm;
      final cur = curve[i].levelCm;
      final next = curve[i + 1].levelCm;
      if (cur >= prev && cur > next) {
        events.add(TideEvent(
            time: curve[i].time,
            levelCm: cur,
            type: TideEventType.high));
      } else if (cur <= prev && cur < next) {
        events.add(TideEvent(
            time: curve[i].time, levelCm: cur, type: TideEventType.low));
      }
    }
    // 10분 간격 극값이 평평한 구간에서 중복될 수 있어 근접 이벤트 병합
    final merged = <TideEvent>[];
    for (final e in events) {
      if (merged.isNotEmpty &&
          merged.last.type == e.type &&
          e.time.difference(merged.last.time).inMinutes < 90) {
        continue;
      }
      merged.add(e);
    }
    return merged;
  }
}
