/// KHOA 바다누리 해양정보 오픈API 클라이언트.
///
/// 요청 형식:
///   http://www.khoa.go.kr/api/oceangrid/{DataType}/search.do
///     ?ServiceKey=키&ObsCode=DT_0001&Date=20260718&ResultType=json
///
/// 사용 DataType:
///   - tideObsPreTab : 조석예보 고·저조 (만조/간조 시각·조위)
///   - tideObsPre    : 조석예보 시계열 (예측 조위 곡선)
///   - tideObsTemp   : 조위관측소 실측 수온
///   - tideObsWind   : 조위관측소 실측 풍향/풍속
///   - ObsServiceObj : 관측소 목록
///
/// 응답 JSON 필드명이 문서 개정으로 달라질 수 있어 필드 후보를
/// 복수로 두고 매핑한다 (_pick 참조).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class KhoaApiException implements Exception {
  final String message;
  KhoaApiException(this.message);
  @override
  String toString() => 'KhoaApiException: $message';
}

class KhoaApi {
  static const _base = 'http://www.khoa.go.kr/api/oceangrid';
  final String serviceKey;
  final http.Client _client;

  KhoaApi(this.serviceKey, {http.Client? client})
      : _client = client ?? http.Client();

  Future<List<dynamic>> _fetchData(String dataType,
      {Map<String, String> params = const {}}) async {
    final uri = Uri.parse('$_base/$dataType/search.do').replace(
      queryParameters: {
        'ServiceKey': serviceKey,
        'ResultType': 'json',
        ...params,
      },
    );
    final res = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw KhoaApiException('HTTP ${res.statusCode} for $dataType');
    }
    final body = res.body.trim();
    if (!body.startsWith('{') && !body.startsWith('[')) {
      // 인증키 오류 등은 HTML 오류 페이지로 돌아온다.
      throw KhoaApiException('비정상 응답(HTML) — 인증키를 확인하세요');
    }
    final j = json.decode(body) as Map<String, dynamic>;
    final result = j['result'];
    if (result is! Map<String, dynamic>) {
      throw KhoaApiException('예상 밖 응답 구조: ${body.substring(0, 80)}');
    }
    if (result['error'] != null) {
      throw KhoaApiException('API 오류: ${result['error']}');
    }
    final data = result['data'];
    if (data is List) return data;
    if (data is Map) return [data];
    return const [];
  }

  static String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null) return v.toString();
    }
    return '';
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  /// 만조/간조 (조석예보 고저조).
  Future<List<TideEvent>> fetchHighLow(String obsCode, DateTime date) async {
    final data = await _fetchData('tideObsPreTab', params: {
      'ObsCode': obsCode,
      'Date': _fmtDate(date),
    });
    final events = <TideEvent>[];
    for (final row in data.cast<Map<String, dynamic>>()) {
      final timeStr = _pick(row, ['tph_time', 'record_time']);
      final levelStr = _pick(row, ['tph_level', 'tide_level']);
      final code = _pick(row, ['hl_code', 'code']);
      final time = DateTime.tryParse(timeStr);
      final level = double.tryParse(levelStr);
      if (time == null || level == null) continue;
      final isHigh = code.contains('고');
      events.add(TideEvent(
        time: time,
        levelCm: level,
        type: isHigh ? TideEventType.high : TideEventType.low,
      ));
    }
    events.sort((a, b) => a.time.compareTo(b.time));
    return events;
  }

  /// 예측 조위 시계열 (곡선용).
  Future<List<TidePoint>> fetchTideCurve(String obsCode, DateTime date) async {
    final data = await _fetchData('tideObsPre', params: {
      'ObsCode': obsCode,
      'Date': _fmtDate(date),
    });
    final points = <TidePoint>[];
    for (final row in data.cast<Map<String, dynamic>>()) {
      final time = DateTime.tryParse(_pick(row, ['record_time', 'pre_time']));
      final level =
          double.tryParse(_pick(row, ['pre_value', 'tide_level', 'pre_level']));
      if (time == null || level == null) continue;
      points.add(TidePoint(time, level));
    }
    points.sort((a, b) => a.time.compareTo(b.time));
    // 1분 간격이면 하루 1440개 — 곡선 그리기에는 10분 간격이면 충분하다.
    if (points.length > 300) {
      final thinned = <TidePoint>[];
      for (var i = 0; i < points.length; i += 10) {
        thinned.add(points[i]);
      }
      return thinned;
    }
    return points;
  }

  /// 실측 수온 (최신 값).
  Future<double?> fetchWaterTemp(String obsCode) async {
    try {
      final data = await _fetchData('tideObsTemp', params: {
        'ObsCode': obsCode,
        'Date': _fmtDate(DateTime.now()),
      });
      if (data.isEmpty) return null;
      final last = data.last as Map<String, dynamic>;
      return double.tryParse(_pick(last, ['water_temp', 'temp']));
    } on KhoaApiException {
      return null; // 수온 미관측 지점
    }
  }

  /// 실측 풍향/풍속 (최신 값). (풍속 m/s, 풍향 도)
  Future<(double?, double?)> fetchWind(String obsCode) async {
    try {
      final data = await _fetchData('tideObsWind', params: {
        'ObsCode': obsCode,
        'Date': _fmtDate(DateTime.now()),
      });
      if (data.isEmpty) return (null, null);
      final last = data.last as Map<String, dynamic>;
      final speed = double.tryParse(_pick(last, ['wind_speed', 'speed']));
      final dir = double.tryParse(_pick(last, ['wind_dir', 'wind_direct', 'dir']));
      return (speed, dir);
    } on KhoaApiException {
      return (null, null);
    }
  }

  /// 조위관측소 목록.
  Future<List<Station>> fetchStations() async {
    final data = await _fetchData('ObsServiceObj');
    final stations = <Station>[];
    for (final row in data.cast<Map<String, dynamic>>()) {
      final id = _pick(row, ['obs_post_id', 'obs_id']);
      final name = _pick(row, ['obs_post_name', 'obs_name']);
      final lat = double.tryParse(_pick(row, ['obs_lat', 'lat']));
      final lon = double.tryParse(_pick(row, ['obs_lon', 'lon']));
      final objType = _pick(row, ['data_type', 'obs_object']);
      if (id.isEmpty || name.isEmpty || lat == null || lon == null) continue;
      // 조위관측소(DT_*)만 사용
      if (!id.startsWith('DT')) continue;
      // 같은 관측소가 데이터 종류별로 여러 행 올 수 있어 중복 제거
      if (stations.any((s) => s.code == id)) continue;
      if (objType.isNotEmpty && !objType.contains('조위')) {
        // data_type 필드가 있으면 조위 제공 지점만
        if (!objType.toLowerCase().contains('tide')) continue;
      }
      stations.add(Station(code: id, name: name, lat: lat, lon: lon));
    }
    stations.sort((a, b) => a.name.compareTo(b.name));
    return stations;
  }
}
