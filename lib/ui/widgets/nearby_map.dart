import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/models.dart';
import '../theme.dart';
import 'place_actions.dart';

/// 주변 5km 지도 — 지점 핀 + 반경 원 + 화장실/낚시점/편의점 마커,
/// 그리고 윈디(Windy) 스타일의 바람 입자 애니메이션 오버레이.
///
/// 타일은 OpenStreetMap(무료)을 쓰고, 마커 데이터는 카카오 로컬이다.
class NearbyMap extends StatefulWidget {
  final Station station;
  final NearbyInfo info;
  final double? windSpeedMs;
  final double? windDirDeg;

  const NearbyMap({
    super.key,
    required this.station,
    required this.info,
    this.windSpeedMs,
    this.windDirDeg,
  });

  @override
  State<NearbyMap> createState() => _NearbyMapState();
}

class _NearbyMapState extends State<NearbyMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wind =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();

  @override
  void dispose() {
    _wind.dispose();
    super.dispose();
  }

  /// 색상 블릿 마커 — 탭하면 지도앱 연결 팝업.
  Marker _placeMarker(
      BuildContext context, NearbyPlace p, Color color, String label) {
    return Marker(
      point: LatLng(p.lat, p.lon),
      width: 22,
      height: 22,
      child: GestureDetector(
        onTap: () => showPlaceActions(
          context,
          place: p,
          color: color,
          typeLabel: label,
          fromName: widget.station.name,
        ),
        child: Center(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: surface1, width: 2),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black38,
                    blurRadius: 3,
                    offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: caption.copyWith(color: ink, fontSize: 10)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.station.lat, widget.station.lon);
    final speed = widget.windSpeedMs;
    final dir = widget.windDirDeg;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radiusLg),
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 11.6, // 반경 5km가 화면에 들어오는 줌
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.bitewind.app',
                ),
                CircleLayer(circles: [
                  CircleMarker(
                    point: center,
                    radius: 5000,
                    useRadiusInMeter: true,
                    color: reportBlue.withValues(alpha: 0.06),
                    borderColor: reportBlue.withValues(alpha: 0.6),
                    borderStrokeWidth: 1.5,
                  ),
                ]),
                MarkerLayer(markers: [
                  Marker(
                    point: center,
                    width: 36,
                    height: 36,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.place, color: ink, size: 34),
                  ),
                  for (final p in widget.info.convenienceStores)
                    _placeMarker(context, p, nearbyStoreColor, '편의점'),
                  for (final p in widget.info.toilets)
                    _placeMarker(context, p, nearbyToiletColor, '화장실'),
                  for (final p in widget.info.fishingShops)
                    _placeMarker(context, p, nearbyShopColor, '낚시점'),
                ]),
                const Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Text(
                      '© OpenStreetMap',
                      style: TextStyle(fontSize: 9, color: inkSubtle),
                    ),
                  ),
                ),
              ],
            ),
            // 윈디 스타일 바람 입자 오버레이
            if (speed != null && dir != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _WindParticlesPainter(
                      animation: _wind,
                      speedMs: speed,
                      dirDeg: dir,
                    ),
                  ),
                ),
              ),
            // 범례 (블릿 색상 안내)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: surface1.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(radiusXs),
                  border: Border.all(color: hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _legendItem(nearbyToiletColor, '화장실'),
                    const SizedBox(width: 8),
                    _legendItem(nearbyStoreColor, '편의점'),
                    const SizedBox(width: 8),
                    _legendItem(nearbyShopColor, '낚시점'),
                  ],
                ),
              ),
            ),
            // 풍향·풍속 칩
            if (speed != null)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(radiusMd),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (dir != null)
                        Transform.rotate(
                          angle: (dir + 180) * math.pi / 180,
                          child: const Icon(Icons.navigation,
                              color: onPrimary, size: 13),
                        ),
                      const SizedBox(width: 5),
                      Text(
                        '${windDirText(dir)}풍 ${speed.toStringAsFixed(1)}m/s',
                        style: caption.copyWith(
                            color: onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 바람 방향으로 흐르는 스트릭(입자 꼬리) 애니메이션.
///
/// 풍속이 빠를수록 입자가 빨리 움직이고 꼬리가 길어지며 색이 진해진다.
/// (약풍 흰색 → 중풍 파랑 → 강풍 주황 → 폭풍 핑크)
class _WindParticlesPainter extends CustomPainter {
  final Animation<double> animation;
  final double speedMs;
  final double dirDeg;

  static const _count = 42;
  final List<double> _randU;
  final List<double> _randV;

  _WindParticlesPainter({
    required this.animation,
    required this.speedMs,
    required this.dirDeg,
  })  : _randU = List.generate(
            _count, (i) => math.Random(i * 7919 + 17).nextDouble()),
        _randV = List.generate(
            _count, (i) => math.Random(i * 104729 + 3).nextDouble()),
        super(repaint: animation);

  Color _speedColor(double s) {
    if (s < 3) return Colors.white;
    if (s < 7) return const Color(0xFF1E6FD0); // 진한 파랑 (바다 타일과 대비)
    if (s < 12) return const Color(0xFFF6A609); // 앰버
    return const Color(0xFFFF2067); // report-pink
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 바람이 "가는" 방향 (기상 풍향은 불어오는 방향)
    final angle = (dirDeg + 180) * math.pi / 180;
    // 화면 좌표: 북=위 → dx = sin, dy = -cos
    final dx = math.sin(angle);
    final dy = -math.cos(angle);

    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    // 한 사이클(8초) 동안 이동 거리 — 풍속 비례
    final cycleDist = diag * (0.4 + speedMs * 0.12);
    final t = animation.value;

    final streakLen = (8.0 + speedMs * 2.5).clamp(8.0, 40.0);
    final color = _speedColor(speedMs);

    final shadow = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2, cy = size.height / 2;
    // 바람 축(u)·수직 축(v) 좌표계에서 입자를 움직이고 화면으로 회전 변환
    final ux = dx, uy = dy; // u 단위벡터
    final vx = -dy, vy = dx; // v 단위벡터

    for (var i = 0; i < _count; i++) {
      final u = ((_randU[i] * diag + t * cycleDist) % (diag + streakLen)) -
          (diag + streakLen) / 2;
      final v = (_randV[i] - 0.5) * diag;
      final x = cx + u * ux + v * vx;
      final y = cy + u * uy + v * vy;
      final tail = Offset(x - dx * streakLen, y - dy * streakLen);
      final head = Offset(x, y);
      canvas.drawLine(tail, head, shadow); // 흰 언더레이로 어떤 배경에서도 보이게
      canvas.drawLine(tail, head, line);
      // 머리 쪽 점 — 진행 방향 강조
      canvas.drawCircle(head, 2.2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_WindParticlesPainter oldDelegate) =>
      oldDelegate.speedMs != speedMs || oldDelegate.dirDeg != dirDeg;
}
