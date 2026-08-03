import 'package:flutter/foundation.dart' show kIsWeb;

/// CORS를 지원하지 않는 API(예: apis.data.go.kr)를 **웹**에서 호출하기 위한
/// 프록시 래핑. 모바일/데스크톱(네이티브)에선 CORS 제약이 없으므로 원본 그대로.
///
/// ⚠️ 웹에서는 요청 URL(서비스키 포함)이 공개 프록시를 경유한다. 어차피 웹
/// 번들에 키가 노출되는 데모 특성상 감수. 운영에선 자체 프록시(Cloudflare
/// Worker 등)로 교체 권장.
Uri corsSafe(Uri original) {
  if (!kIsWeb) return original;
  final encoded = Uri.encodeComponent(original.toString());
  return Uri.parse('https://corsproxy.io/?url=$encoded');
}
