/// 지점 주변 편의시설 검색 — 카카오 로컬 키워드 검색.
///
/// 좌표 + radius(m) + 거리순 정렬로 반경 5km 내
/// 화장실·낚시점·편의점을 찾는다.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class NearbyApi {
  static const _radiusM = 5000;
  final String kakaoRestApiKey;
  final http.Client _client;

  NearbyApi(this.kakaoRestApiKey, {http.Client? client})
      : _client = client ?? http.Client();

  Future<List<NearbyPlace>> _search(double lat, double lon,
      {String? query, String? categoryCode}) async {
    final uri = Uri.https(
        'dapi.kakao.com',
        categoryCode != null
            ? '/v2/local/search/category.json'
            : '/v2/local/search/keyword.json',
        {
          'query': ?query,
          'category_group_code': ?categoryCode,
          'x': '$lon',
          'y': '$lat',
          'radius': '$_radiusM',
          'sort': 'distance',
          'size': '15',
        });
    final res = await _client.get(uri, headers: {
      'Authorization': 'KakaoAK $kakaoRestApiKey',
    }).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return const [];
    final j = json.decode(res.body) as Map<String, dynamic>;
    final docs = j['documents'] as List? ?? const [];
    final out = <NearbyPlace>[];
    for (final d in docs.cast<Map<String, dynamic>>()) {
      final name = d['place_name']?.toString() ?? '';
      final dist = double.tryParse(d['distance']?.toString() ?? '');
      final pLat = double.tryParse(d['y']?.toString() ?? '');
      final pLon = double.tryParse(d['x']?.toString() ?? '');
      if (name.isEmpty || dist == null || pLat == null || pLon == null) {
        continue;
      }
      out.add(NearbyPlace(
        name: name,
        address: (d['road_address_name']?.toString().isNotEmpty == true
                ? d['road_address_name']
                : d['address_name'])
            ?.toString() ??
            '',
        distanceM: dist,
        lat: pLat,
        lon: pLon,
      ));
    }
    return out;
  }

  /// 반경 5km 내 화장실·낚시점·편의점.
  Future<NearbyInfo> fetch(double lat, double lon) async {
    final results = await Future.wait([
      _search(lat, lon, query: '화장실'),
      _search(lat, lon, query: '낚시'),
      _search(lat, lon, categoryCode: 'CS2'), // 편의점 카테고리
    ]);
    // '낚시' 검색에는 낚시터·횟집 등이 섞일 수 있어 카테고리성 상호만 남기는
    // 대신 상호에 낚시가 들어간 곳을 그대로 보여준다 (현장 판단에 유용).
    return NearbyInfo(
      toilets: results[0],
      fishingShops: results[1],
      convenienceStores: results[2],
    );
  }
}
