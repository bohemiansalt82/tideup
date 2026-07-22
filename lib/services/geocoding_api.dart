/// 지명 검색 (지오코딩).
///
/// 1순위: 카카오 로컬 키워드 검색 — 키가 있으면 사용. 국내 소규모 어항·
///        방조제·낚시 포인트까지 커버리지가 좋다.
/// 폴백:  OpenStreetMap Nominatim — 키 없이 사용 가능하지만 한국 POI가
///        성기다. 요청은 검색창 디바운스로 제한된다 (초당 1회 수준).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class GeoPlace {
  final String name; // 짧은 이름 (예: 월미도)
  final String region; // 행정구역 맥락 (예: 중구, 인천광역시)
  final String type; // 해변/항구/선착장/섬/지역 …
  final double lat;
  final double lon;

  const GeoPlace({
    required this.name,
    required this.region,
    required this.type,
    required this.lat,
    required this.lon,
  });
}

class GeocodingApi {
  final String kakaoRestApiKey;
  final http.Client _client;

  GeocodingApi({this.kakaoRestApiKey = '', http.Client? client})
      : _client = client ?? http.Client();

  static String _typeOf(String osmClass, String osmType) {
    if (osmType == 'beach') return '해변';
    if (osmType == 'harbour' || osmType == 'port') return '항구';
    if (osmType == 'pier' || osmType == 'ferry_terminal') return '선착장';
    if (osmType == 'marina') return '마리나';
    if (osmType == 'island' || osmType == 'islet') return '섬';
    if (osmType == 'breakwater') return '방파제';
    if (osmClass == 'natural') return '자연';
    return '지역';
  }

  /// 카카오 카테고리명 → 앱 표시 유형.
  static String _typeOfKakao(String categoryName) {
    if (categoryName.contains('해수욕장')) return '해수욕장';
    if (categoryName.contains('항구') || categoryName.contains('포구')) {
      return '항구';
    }
    if (categoryName.contains('방파제')) return '방파제';
    if (categoryName.contains('방조제')) return '방조제';
    if (categoryName.contains('섬')) return '섬';
    if (categoryName.contains('낚시')) return '낚시터';
    if (categoryName.contains('선착장') || categoryName.contains('여객')) {
      return '선착장';
    }
    if (categoryName.contains('해변') || categoryName.contains('해안')) {
      return '해변';
    }
    return '지역';
  }

  Future<List<GeoPlace>> search(String query) async {
    if (kakaoRestApiKey.isNotEmpty) {
      try {
        final results = await _searchKakao(query);
        if (results.isNotEmpty) return results;
      } catch (_) {
        // 카카오 실패 → Nominatim 폴백
      }
    }
    return _searchNominatim(query);
  }

  Future<List<GeoPlace>> _searchKakao(String query) async {
    final uri = Uri.https('dapi.kakao.com', '/v2/local/search/keyword.json', {
      'query': query,
      'size': '10',
    });
    final res = await _client.get(uri, headers: {
      'Authorization': 'KakaoAK $kakaoRestApiKey',
    }).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('kakao ${res.statusCode}');
    }
    final j = json.decode(res.body) as Map<String, dynamic>;
    final docs = j['documents'] as List? ?? const [];
    final out = <GeoPlace>[];
    for (final d in docs.cast<Map<String, dynamic>>()) {
      final lat = double.tryParse(d['y']?.toString() ?? '');
      final lon = double.tryParse(d['x']?.toString() ?? '');
      final name = d['place_name']?.toString() ?? '';
      if (lat == null || lon == null || name.isEmpty) continue;
      // 주소에서 시/군 단위까지만 맥락으로
      final addr = (d['address_name']?.toString() ?? '').split(' ');
      out.add(GeoPlace(
        name: name,
        region: addr.take(2).join(' '),
        type: _typeOfKakao(d['category_name']?.toString() ?? ''),
        lat: lat,
        lon: lon,
      ));
    }
    return out;
  }

  Future<List<GeoPlace>> _searchNominatim(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'countrycodes': 'kr',
      'limit': '10',
      'accept-language': 'ko',
    });
    final res = await _client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return const [];
    final list = json.decode(res.body) as List;
    final out = <GeoPlace>[];
    for (final row in list.cast<Map<String, dynamic>>()) {
      final lat = double.tryParse(row['lat']?.toString() ?? '');
      final lon = double.tryParse(row['lon']?.toString() ?? '');
      if (lat == null || lon == null) continue;
      final display = (row['display_name'] as String? ?? '').split(', ');
      final name = (row['name'] as String?)?.trim().isNotEmpty == true
          ? row['name'] as String
          : (display.isNotEmpty ? display.first : query);
      // display_name 중간 부분을 행정구역 맥락으로 (국가 제외)
      final region = display.length > 2
          ? display.sublist(1, display.length - 1).take(2).join(' ')
          : '';
      out.add(GeoPlace(
        name: name,
        region: region,
        type: _typeOf(
            row['class']?.toString() ?? '', row['type']?.toString() ?? ''),
        lat: lat,
        lon: lon,
      ));
    }
    return out;
  }
}
