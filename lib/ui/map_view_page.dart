import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:latlong2/latlong.dart';

import '../services/map_field_api.dart';
import 'theme.dart';

// 솔리드(평면) 지도 색 — 밝은 바람/수온 표시가 잘 보이도록 어둡게.
const _seaColor = Color(0xFF0E1A2B);
const _landColor = Color(0xFF25384D);
const _coastColor = Color(0xFF3C526B);

/// 전체 지도 보기 — 아이폰 날씨 지도처럼 바람 흐름/수온 레이어를 시간별로 본다.
class MapViewPage extends StatefulWidget {
  const MapViewPage({super.key});

  @override
  State<MapViewPage> createState() => _MapViewPageState();
}

enum _Layer { wind, temp }

class _MapViewPageState extends State<MapViewPage>
    with SingleTickerProviderStateMixin {
  final _mapController = MapController();
  final _api = MapFieldApi();
  late final AnimationController _anim;

  MapField? _field;
  Object? _error;
  _Layer _layer = _Layer.wind;
  int _hour = 0;
  final List<_P> _particles = [];
  final _rng = math.Random();
  Duration _lastTick = Duration.zero;
  List<List<LatLng>> _land = const [];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(_onTick);
    _anim.repeat();
    _loadLand();
    _load();
  }

  Future<void> _loadLand() async {
    try {
      final raw = await rootBundle.loadString('assets/geo/land_ea.json');
      final data = json.decode(raw) as Map<String, dynamic>;
      final polys = (data['polys'] as List)
          .map((ring) => (ring as List)
              .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
              .toList())
          .toList();
      if (mounted) setState(() => _land = polys);
    } catch (_) {
      // 실패해도 바다색 배경만으로 진행
    }
  }

  Future<void> _load() async {
    try {
      final field = await _api.fetch();
      if (!mounted) return;
      // 현재 시각에 가장 가까운 시간 인덱스
      final now = DateTime.now();
      var idx = 0;
      for (var i = 0; i < field.times.length; i++) {
        if (!field.times[i].isBefore(
            DateTime(now.year, now.month, now.day, now.hour))) {
          idx = i;
          break;
        }
      }
      setState(() {
        _field = field;
        _hour = idx;
      });
      _seedParticles();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _seedParticles() {
    _particles.clear();
    for (var i = 0; i < 520; i++) {
      final p = _randomParticle();
      p.age = _rng.nextInt(p.life).toDouble(); // 수명 분산 → 깜빡임 방지
      _particles.add(p);
    }
  }

  _P _randomParticle() {
    final p = _P(
      lat: 32.8 + _rng.nextDouble() * 6.4,
      lon: 123.8 + _rng.nextDouble() * 7.2,
      life: 70 + _rng.nextInt(110),
    );
    p.trail.add(LatLng(p.lat, p.lon));
    return p;
  }

  void _resetParticle(_P p) {
    p.lat = 32.8 + _rng.nextDouble() * 6.4;
    p.lon = 123.8 + _rng.nextDouble() * 7.2;
    p.age = 0;
    p.life = 70 + _rng.nextInt(110);
    p.trail
      ..clear()
      ..add(LatLng(p.lat, p.lon));
  }

  void _onTick() {
    if (_field == null || _layer != _Layer.wind) return;
    final elapsed = _anim.lastElapsedDuration ?? Duration.zero;
    // 프레임 간격 (초). 첫 프레임은 건너뜀.
    final dt =
        ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    final pts = _field!.points;
    for (final p in _particles) {
      final w = interpolateWind(pts, _hour, p.lat, p.lon);
      if (w != null) {
        final (speed, dirFrom) = w;
        p.spd = speed;
        final angTo = (dirFrom + 180) * math.pi / 180;
        final u = speed * math.sin(angTo); // 동
        final v = speed * math.cos(angTo); // 북
        final k = 0.16 * dt; // 이동 스케일
        p.lat += v * k;
        p.lon += u * k / math.cos(p.lat * math.pi / 180);
      } else {
        p.spd = 0;
      }
      // 꼬리 좌표 누적 (윈디처럼 흐름 선을 남긴다)
      p.trail.add(LatLng(p.lat, p.lon));
      if (p.trail.length > 18) p.trail.removeAt(0);
      p.age += dt * 30;
      if (p.age > p.life ||
          p.lat < 32.5 ||
          p.lat > 39.6 ||
          p.lon < 123.4 ||
          p.lon > 131.6) {
        _resetParticle(p);
      }
    }
    setState(() {}); // 오버레이 리페인트
  }

  @override
  void dispose() {
    _anim.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = _field;
    return Scaffold(
      backgroundColor: _seaColor,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(36.3, 127.8),
              initialZoom: 6.3,
              minZoom: 5,
              maxZoom: 10,
              backgroundColor: _seaColor,
              interactionOptions:
                  InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              // 솔리드 육지 (해안선 폴리곤을 단색으로 채움)
              if (_land.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    for (final ring in _land)
                      Polygon(
                        points: ring,
                        color: _landColor,
                        borderColor: _coastColor,
                        borderStrokeWidth: 0.6,
                      ),
                  ],
                ),
              // 지명 라벨만 (가독성) — 어두운 배경용, 실패해도 무방
              TileLayer(
                urlTemplate:
                    'https://basemaps.cartocdn.com/dark_only_labels/{z}/{x}/{y}@2x.png',
                userAgentPackageName: 'com.bitewind.app',
                tileProvider: NetworkTileProvider(),
              ),
              // 오버레이 (바람 입자 / 수온 히트맵)
              if (field != null && !field.isEmpty)
                Builder(
                  builder: (ctx) {
                    final cam = MapCamera.of(ctx);
                    return IgnorePointer(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _layer == _Layer.wind
                            ? _WindPainter(cam, _particles)
                            : _TempPainter(cam, field.points, _hour),
                      ),
                    );
                  },
                ),
            ],
          ),

          // 상단: 뒤로가기 + 레이어 토글
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _RoundBtn(
                    icon: Icons.arrow_back_ios_new,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  _LayerToggle(
                    layer: _layer,
                    onChanged: (l) => setState(() => _layer = l),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),

          // 로딩 / 에러
          if (field == null && _error == null)
            const Center(
                child: CircularProgressIndicator(color: Colors.white)),
          if (_error != null)
            const Center(
              child: Text('기상 데이터를 불러오지 못했어요',
                  style: TextStyle(color: Colors.white70)),
            ),

          // 하단: 범례 + 시간 슬라이더
          if (field != null && !field.isEmpty)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _BottomPanel(
                  layer: _layer,
                  times: field.times,
                  hour: _hour,
                  onHour: (h) => setState(() => _hour = h),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 바람 입자 ──────────────────────────────────────────
class _P {
  double lat, lon;
  double age = 0;
  int life;
  double spd = 0;
  final List<LatLng> trail = []; // 오래된→최신 좌표
  _P({required this.lat, required this.lon, required this.life});
}

Color _lerpStops(List<(double, Color)> stops, double v) {
  if (v <= stops.first.$1) return stops.first.$2;
  if (v >= stops.last.$1) return stops.last.$2;
  for (var i = 0; i < stops.length - 1; i++) {
    final a = stops[i], b = stops[i + 1];
    if (v >= a.$1 && v <= b.$1) {
      return Color.lerp(a.$2, b.$2, (v - a.$1) / (b.$1 - a.$1))!;
    }
  }
  return stops.last.$2;
}

// 풍속(m/s) → 윈디풍 그라데이션.
const _windStops = [
  (0.0, Color(0xFF7EC8FF)),
  (3.0, Color(0xFF4FE3C4)),
  (6.0, Color(0xFF86E24C)),
  (9.0, Color(0xFFF2D33E)),
  (12.0, Color(0xFFF39B34)),
  (16.0, Color(0xFFF2503C)),
  (22.0, Color(0xFFB23CC0)),
];

Color windColor(double s) => _lerpStops(_windStops, s);

class _WindPainter extends CustomPainter {
  final MapCamera cam;
  final List<_P> particles;

  _WindPainter(this.cam, this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final p in particles) {
      final tr = p.trail;
      if (tr.length < 2) continue;
      final base = windColor(p.spd);
      final ageFade = (1.0 - (p.age / p.life)).clamp(0.0, 1.0);
      // 꼬리(옅고 가늘게) → 머리(진하고 굵게)
      for (var i = 1; i < tr.length; i++) {
        final a = cam.latLngToScreenOffset(tr[i - 1]);
        final b = cam.latLngToScreenOffset(tr[i]);
        final head = i / (tr.length - 1); // 0=꼬리, 1=머리
        final alpha = (head * head * 0.95 * ageFade).clamp(0.0, 1.0);
        paint
          ..color = base.withValues(alpha: alpha)
          ..strokeWidth = 1.4 + head * 2.8;
        canvas.drawLine(a, b, paint);
      }
      // 머리 점 — 살짝 밝게
      final headPt = cam.latLngToScreenOffset(tr.last);
      canvas.drawCircle(
        headPt,
        2.4,
        Paint()..color = base.withValues(alpha: 0.9 * ageFade),
      );
    }
  }

  @override
  bool shouldRepaint(_WindPainter old) => true;
}

// ── 수온 히트맵 ────────────────────────────────────────
Color tempColor(double t) {
  const stops = [
    (8.0, Color(0xFF2E5BB8)),
    (15.0, Color(0xFF35A7C2)),
    (20.0, Color(0xFF3FB56B)),
    (24.0, Color(0xFFF2B134)),
    (28.0, Color(0xFFE8552B)),
    (32.0, Color(0xFFC2185B)),
  ];
  if (t <= stops.first.$1) return stops.first.$2;
  if (t >= stops.last.$1) return stops.last.$2;
  for (var i = 0; i < stops.length - 1; i++) {
    final a = stops[i], b = stops[i + 1];
    if (t >= a.$1 && t <= b.$1) {
      final f = (t - a.$1) / (b.$1 - a.$1);
      return Color.lerp(a.$2, b.$2, f)!;
    }
  }
  return stops.last.$2;
}

class _TempPainter extends CustomPainter {
  final MapCamera cam;
  final List<FieldPoint> points;
  final int hour;

  _TempPainter(this.cam, this.points, this.hour);

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    // 히트 블롭
    for (final p in points) {
      if (hour >= p.hours.length) continue;
      final t = p.hours[hour].waterTempC;
      if (t == null) continue;
      final o = cam.latLngToScreenOffset(LatLng(p.lat, p.lon));
      canvas.drawCircle(
        o,
        46,
        Paint()
          ..color = tempColor(t).withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34),
      );
    }
    // 값 라벨
    for (final p in points) {
      if (hour >= p.hours.length) continue;
      final t = p.hours[hour].waterTempC;
      if (t == null) continue;
      final o = cam.latLngToScreenOffset(LatLng(p.lat, p.lon));
      tp.text = TextSpan(
        text: '${t.round()}°',
        style: const TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(o.dx - tp.width / 2, o.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_TempPainter old) => old.hour != hour;
}

// ── 컨트롤 위젯 ────────────────────────────────────────
class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _LayerToggle extends StatelessWidget {
  final _Layer layer;
  final ValueChanged<_Layer> onChanged;
  const _LayerToggle({required this.layer, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget pill(_Layer l, IconData icon, String label) {
      final sel = layer == l;
      return GestureDetector(
        onTap: () => onChanged(l),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15, color: sel ? ink : Colors.white),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    color: sel ? ink : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(_Layer.wind, Icons.air, '바람'),
          pill(_Layer.temp, Icons.thermostat, '수온'),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final _Layer layer;
  final List<DateTime> times;
  final int hour;
  final ValueChanged<int> onHour;

  const _BottomPanel({
    required this.layer,
    required this.times,
    required this.hour,
    required this.onHour,
  });

  @override
  Widget build(BuildContext context) {
    final t = hour < times.length ? times[hour] : DateTime.now();
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final label = sameDay
        ? '오늘 ${DateFormat('HH').format(t)}시'
        : '${DateFormat('M/d HH').format(t)}시';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(radiusXl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                layer == _Layer.wind ? '바람 흐름' : '바다 수온',
                style: const TextStyle(
                  fontFamily: fontFamily,
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(label,
                  style: const TextStyle(
                    fontFamily: fontFamily,
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )),
            ],
          ),
          const SizedBox(height: 2),
          if (layer == _Layer.wind)
            const _WindLegend()
          else
            const _TempLegend(),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: hour.toDouble(),
              min: 0,
              max: (times.length - 1).toDouble().clamp(0, 47),
              onChanged: (v) => onHour(v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindLegend extends StatelessWidget {
  const _WindLegend();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Text('0',
              style: TextStyle(
                  fontFamily: fontFamily,
                  color: Colors.white70,
                  fontSize: 10)),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(colors: [
                  windColor(0),
                  windColor(4),
                  windColor(7),
                  windColor(10),
                  windColor(14),
                  windColor(18),
                  windColor(22),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text('20㎧+',
              style: TextStyle(
                  fontFamily: fontFamily,
                  color: Colors.white70,
                  fontSize: 10)),
        ],
      ),
    );
  }
}

class _TempLegend extends StatelessWidget {
  const _TempLegend();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Text('10°',
              style: TextStyle(
                  fontFamily: fontFamily,
                  color: Colors.white70,
                  fontSize: 10)),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(colors: [
                  tempColor(10),
                  tempColor(17),
                  tempColor(22),
                  tempColor(26),
                  tempColor(30),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text('30°',
              style: TextStyle(
                  fontFamily: fontFamily,
                  color: Colors.white70,
                  fontSize: 10)),
        ],
      ),
    );
  }
}
