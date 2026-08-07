import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// CORS를 지원하지 않는 API(예: apis.data.go.kr)를 호출한다.
///
/// - 모바일/데스크톱(네이티브): CORS 제약이 없으므로 직접 요청.
/// - 웹: 공개 CORS 프록시를 경유. 하나가 죽어도 다음으로 폴백한다.
///
/// ⚠️ 웹에서는 요청 URL(서비스키 포함)이 공개 프록시를 경유한다. 데모 특성상
/// 감수하며, 운영에선 자체 프록시(Cloudflare Worker 등)로 교체 권장.
Future<http.Response> corsGet(
  http.Client client,
  Uri original, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (!kIsWeb) return client.get(original).timeout(timeout);

  final enc = Uri.encodeComponent(original.toString());
  final proxies = <Uri>[
    Uri.parse('https://corsproxy.io/?url=$enc'),
    Uri.parse('https://api.allorigins.win/raw?url=$enc'),
  ];
  Object? lastErr;
  for (final p in proxies) {
    try {
      final r = await client.get(p).timeout(timeout);
      if (r.statusCode == 200) return r;
      lastErr = 'HTTP ${r.statusCode}';
    } catch (e) {
      lastErr = e;
    }
  }
  throw Exception('CORS proxy 실패: $lastErr');
}
