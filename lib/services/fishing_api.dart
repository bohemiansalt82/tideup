/// 국립해양조사원 바다낚시지수 API (공공데이터포털).
///
/// End Point: https://apis.data.go.kr/1192136/fcstFishingv2
/// Operation: /GetFcstFishingApiServicev2
/// 파라미터: serviceKey, type=json, reqDate=YYYYMMDD, gubun=갯바위|선상,
///           pageNo, numOfRows
///
/// 응답 item 필드: seafsPstnNm(포인트명), lat/lot(좌표), predcYmd(날짜),
/// predcNoonSeCd(오전/오후), seafsTgfshNm(어종), tdlvHrCn(물때),
/// min/maxWvhgt(파고), min/maxWtem(수온), totalIndex(등급).
///
/// 하루치 전체(약 1,400행)를 한 번 받아 메모리에 캐시하고, 지점 좌표에서
/// 가장 가까운 낚시포인트의 오늘 예보를 골라낸다.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logic/geo.dart';
import '../models/models.dart';

/// 낚시포인트가 이보다 멀면 공식 지수를 보여주지 않는다 (km).
const _maxPointDistanceKm = 40.0;

class FishingApi {
  final String serviceKey;
  final http.Client _client;

  // 날짜별 원본 캐시 (하루 1회만 내려받는다)
  String? _cachedDate;
  List<Map<String, dynamic>> _rows = const [];

  FishingApi(this.serviceKey, {http.Client? client})
      : _client = client ?? http.Client();

  static String _fmtDate(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> _fetchAll(DateTime date) async {
    final dateStr = _fmtDate(date);
    if (_cachedDate == dateStr && _rows.isNotEmpty) return _rows;

    // numOfRows는 300까지만 허용된다 — 전체(약 1,400행)를 페이지로 나눠 받는다.
    final all = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 10) {
      final uri = Uri.https('apis.data.go.kr',
          '/1192136/fcstFishingv2/GetFcstFishingApiServicev2', {
        'serviceKey': serviceKey,
        'type': 'json',
        'reqDate': dateStr,
        'gubun': '갯바위',
        'pageNo': '$page',
        'numOfRows': '300',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) break;
      final j = json.decode(res.body) as Map<String, dynamic>;
      if ((j['header'] as Map?)?['resultCode'] != '00') break;
      final body = j['body'] as Map?;
      final items = (body?['items'] as Map?)?['item'] as List? ?? const [];
      all.addAll(items.cast<Map<String, dynamic>>());
      final total = (body?['totalCount'] as num?)?.toInt() ?? 0;
      if (items.isEmpty || all.length >= total) break;
      page++;
    }
    if (all.isNotEmpty) {
      _rows = all;
      _cachedDate = dateStr;
    }
    return all;
  }

  /// 좌표에서 가장 가까운 낚시포인트의 오늘 예보.
  /// 포인트가 너무 멀거나(>40km) 데이터가 없으면 null.
  Future<FishingForecast?> fetchNearest(
      double lat, double lon, DateTime date) async {
    final rows = await _fetchAll(date);
    if (rows.isEmpty) return null;

    // 포인트별 좌표 수집
    final points = <String, (double, double)>{};
    for (final r in rows) {
      final name = r['seafsPstnNm']?.toString();
      final pLat = (r['lat'] as num?)?.toDouble();
      final pLon = (r['lot'] as num?)?.toDouble();
      if (name == null || pLat == null || pLon == null) continue;
      points[name] = (pLat, pLon);
    }
    if (points.isEmpty) return null;

    String? nearestName;
    var best = double.infinity;
    for (final e in points.entries) {
      final d = haversineKm(lat, lon, e.value.$1, e.value.$2);
      if (d < best) {
        best = d;
        nearestName = e.key;
      }
    }
    if (nearestName == null || best > _maxPointDistanceKm) return null;

    // 해당 포인트의 오늘 데이터만: 어종 → (오전, 오후)
    final dateIso =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final bySpecies = <String, List<String?>>{};
    String? tidePhase;
    for (final r in rows) {
      if (r['seafsPstnNm'] != nearestName) continue;
      if (r['predcYmd']?.toString() != dateIso) continue;
      // 어종 구분이 없는 포인트는 seafsTgfshNm이 '-'로 온다 → '종합' 표기
      var species = (r['seafsTgfshNm']?.toString() ?? '').trim();
      if (species.isEmpty || species == '-') species = '종합';
      final grade = r['totalIndex']?.toString();
      final noon = r['predcNoonSeCd']?.toString();
      tidePhase ??= r['tdlvHrCn']?.toString();
      final slot = bySpecies.putIfAbsent(species, () => [null, null]);
      if (noon == '오전') {
        slot[0] = grade;
      } else {
        slot[1] = grade;
      }
    }
    if (bySpecies.isEmpty) return null;

    final list = bySpecies.entries
        .map((e) => FishingSpeciesIndex(
              species: e.key,
              morning: e.value[0],
              afternoon: e.value[1],
            ))
        .toList()
      ..sort((a, b) => a.species.compareTo(b.species));

    return FishingForecast(
      pointName: nearestName,
      distanceKm: best,
      tidePhase: tidePhase,
      species: list,
    );
  }
}
