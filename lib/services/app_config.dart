/// API 키 설정 로더.
///
/// assets/config/api_keys.json 에서 키를 읽는다:
/// {
///   "khoaServiceKey": "바다누리 인증키 (조석·수온·바람)",
///   "kmaServiceKey": "공공데이터포털 기상청 단기예보 인증키 (선택)",
///   "dataGoKrServiceKey": "공공데이터포털 인증키 (바다낚시지수 등, 선택)"
/// }
/// khoaServiceKey가 비어 있으면 조석은 목업 데이터로 동작한다.
/// 공공데이터포털 키는 Decoding(원본) 키를 넣는다 — URL 인코딩은 앱이 한다.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class AppConfig {
  final String khoaServiceKey;
  final String kmaServiceKey;
  final String dataGoKrServiceKey;
  final String kakaoRestApiKey; // 카카오 로컬 검색 (장소 지오코딩)

  const AppConfig({
    this.khoaServiceKey = '',
    this.kmaServiceKey = '',
    this.dataGoKrServiceKey = '',
    this.kakaoRestApiKey = '',
  });

  bool get hasKhoaKey => khoaServiceKey.isNotEmpty;
  bool get hasKmaKey => kmaServiceKey.isNotEmpty;
  bool get hasDataGoKrKey => dataGoKrServiceKey.isNotEmpty;
  bool get hasKakaoKey => kakaoRestApiKey.isNotEmpty;

  static Future<AppConfig> load() async {
    try {
      final raw = await rootBundle.loadString('assets/config/api_keys.json');
      final j = json.decode(raw) as Map<String, dynamic>;
      return AppConfig(
        khoaServiceKey: (j['khoaServiceKey'] as String? ?? '').trim(),
        kmaServiceKey: (j['kmaServiceKey'] as String? ?? '').trim(),
        dataGoKrServiceKey:
            (j['dataGoKrServiceKey'] as String? ?? '').trim(),
        kakaoRestApiKey: (j['kakaoRestApiKey'] as String? ?? '').trim(),
      );
    } catch (_) {
      return const AppConfig();
    }
  }
}
