import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../theme.dart';

/// 주변 장소를 탭했을 때 — 네이버지도 / 카카오맵 / 티맵으로 여는 팝업.
Future<void> showPlaceActions(
  BuildContext context, {
  required NearbyPlace place,
  required Color color,
  required String typeLabel,
  required String fromName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: surface1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
    ),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(place.name,
                    style: cardTitle.copyWith(fontSize: 19)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$typeLabel · $fromName에서 ${place.distanceM >= 1000 ? '${(place.distanceM / 1000).toStringAsFixed(1)}km' : '${place.distanceM.round()}m'}',
            style: bodySm.copyWith(color: inkMuted),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _MapAppButton(
                  label: '네이버지도',
                  onTap: () => _openNaver(sheetContext, place),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MapAppButton(
                  label: '카카오맵',
                  onTap: () => _openKakao(sheetContext, place),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MapAppButton(
                  label: '티맵',
                  onTap: () => _openTmap(sheetContext, place),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _MapAppButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MapAppButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: hairline),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd)),
        textStyle: buttonText.copyWith(fontSize: 13),
      ),
      child: Text(label),
    );
  }
}

Future<void> _launch(BuildContext context, Uri appUri,
    {Uri? fallback, String? failMessage}) async {
  try {
    final ok = await launchUrl(appUri, mode: LaunchMode.externalApplication);
    if (ok) return;
  } catch (_) {}
  if (fallback != null) {
    try {
      // 웹/미설치 환경 폴백 — 플랫폼 기본 방식(웹은 새 탭)으로 연다
      await launchUrl(fallback, mode: LaunchMode.platformDefault);
      return;
    } catch (_) {}
  }
  if (context.mounted && failMessage != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failMessage)),
    );
  }
}

Future<void> _openNaver(BuildContext context, NearbyPlace p) {
  final name = Uri.encodeComponent(p.name);
  return _launch(
    context,
    Uri.parse(
        'nmap://place?lat=${p.lat}&lng=${p.lon}&name=$name&appname=com.bitewind.app'),
    fallback: Uri.parse('https://map.naver.com/p/search/$name'),
  );
}

Future<void> _openKakao(BuildContext context, NearbyPlace p) {
  final name = Uri.encodeComponent(p.name);
  // kakaomap:// 커스텀 스킴은 잘 안 열려서, 웹·모바일(앱 설치 시 자동 실행)
  // 모두 동작하는 https 링크를 바로 사용한다.
  return _launch(
    context,
    Uri.parse('https://map.kakao.com/link/map/$name,${p.lat},${p.lon}'),
    failMessage: '카카오맵을 열 수 없어요',
  );
}

Future<void> _openTmap(BuildContext context, NearbyPlace p) {
  final name = Uri.encodeComponent(p.name);
  return _launch(
    context,
    Uri.parse('tmap://route?goalname=$name&goaly=${p.lat}&goalx=${p.lon}'),
    failMessage: '티맵 앱이 설치되어 있지 않아요',
  );
}
