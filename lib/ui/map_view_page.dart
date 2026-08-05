import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:latlong2/latlong.dart';

import '../services/map_field_api.dart';
import 'theme.dart';

// 밝은 베이스 지도 — 데이터 컬러(바람 파랑 / 수온 주황)가 잘 얹히도록.
const _seaColor = Color(0xFFD8E3EC);
const _landColor = Color(0xFFE7ECEF);
const _coastColor = Color(0xFFBAC6CF);
const _labelInk = Color(0xFF243441);

/// 지도에 값 버블/라벨을 그릴 주요 도시. (이름, 위도, 경도, 대표도시 여부)
const List<(String, double, double, bool)> _cities = [
  ('서울', 37.5665, 126.9780, true),
  ('인천', 37.4563, 126.7052, true),
  ('수원', 37.2636, 127.0286, true),
  ('춘천', 37.8813, 127.7300, true),
  ('강릉', 37.7519, 128.8761, true),
  ('원주', 37.3422, 127.9202, true),
  ('청주', 36.6424, 127.4890, true),
  ('대전', 36.3504, 127.3845, true),
  ('세종', 36.4801, 127.2890, false),
  ('천안', 36.8151, 127.1139, false),
  ('당진', 36.8898, 126.6457, true),
  ('전주', 35.8242, 127.1480, true),
  ('군산', 35.9676, 126.7370, false),
  ('광주', 35.1595, 126.8526, true),
  ('목포', 34.8118, 126.3922, false),
  ('여수', 34.7604, 127.6622, false),
  ('순천', 34.9506, 127.4872, false),
  ('대구', 35.8714, 128.6014, true),
  ('포항', 36.0190, 129.3435, true),
  ('경주', 35.8562, 129.2247, false),
  ('울산', 35.5384, 129.3114, true),
  ('부산', 35.1796, 129.0756, true),
  ('창원', 35.2280, 128.6811, true),
  ('진주', 35.1800, 128.1076, false),
  ('거제', 34.8807, 128.6210, false),
  ('제주', 33.4996, 126.5312, true),
  ('서귀포', 33.2541, 126.5600, false),
  ('고성', 38.3800, 128.4680, true),
  ('동해', 37.5247, 129.1143, false),
];

/// 전체 지도 보기 — 윈디 스타일. 시간별 바람 흐름/수온을 본다.
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
  Timer? _playTimer;

  bool get _playing => _playTimer != null;

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
              .map((p) =>
                  LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
              .toList())
          .toList();
      if (mounted) setState(() => _land = polys);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final field = await _api.fetch();
      if (!mounted) return;
      final now = DateTime.now();
      var idx = 0;
      for (var i = 0; i < field.times.length; i++) {
        if (!field.times[i]
            .isBefore(DateTime(now.year, now.month, now.day, now.hour))) {
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
      p.age = _rng.nextInt(p.life).toDouble();
      _particles.add(p);
    }
  }

  _P _randomParticle() {
    final p = _P(
      lat: 33.0 + _rng.nextDouble() * 5.7,
      lon: 125.2 + _rng.nextDouble() * 4.8,
      life: 70 + _rng.nextInt(110),
    );
    p.trail.add(LatLng(p.lat, p.lon));
    return p;
  }

  void _resetParticle(_P p) {
    p.lat = 33.0 + _rng.nextDouble() * 5.7;
    p.lon = 125.2 + _rng.nextDouble() * 4.8;
    p.age = 0;
    p.life = 70 + _rng.nextInt(110);
    p.trail
      ..clear()
      ..add(LatLng(p.lat, p.lon));
  }

  void _onTick() {
    if (_field == null || _layer != _Layer.wind) return;
    final elapsed = _anim.lastElapsedDuration ?? Duration.zero;
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    final pts = _field!.points;
    for (final p in _particles) {
      final w = interpolateWind(pts, _hour, p.lat, p.lon);
      if (w != null) {
        final (speed, dirFrom) = w;
        p.spd = speed;
        final angTo = (dirFrom + 180) * math.pi / 180;
        final u = speed * math.sin(angTo);
        final v = speed * math.cos(angTo);
        final k = 0.16 * dt;
        p.lat += v * k;
        p.lon += u * k / math.cos(p.lat * math.pi / 180);
      } else {
        p.spd = 0;
      }
      p.trail.add(LatLng(p.lat, p.lon));
      if (p.trail.length > 18) p.trail.removeAt(0);
      p.age += dt * 30;
      if (p.age > p.life ||
          p.lat < 32.9 ||
          p.lat > 38.8 ||
          p.lon < 124.9 ||
          p.lon > 130.4) {
        _resetParticle(p);
      }
    }
    setState(() {});
  }

  void _togglePlay() {
    setState(() {
      if (_playTimer != null) {
        _playTimer!.cancel();
        _playTimer = null;
      } else {
        _playTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
          final n = _field?.times.length ?? 0;
          if (n == 0) return;
          setState(() => _hour = (_hour + 1) % n);
        });
      }
    });
  }

  void _zoomBy(double delta) {
    final c = _mapController.camera;
    _mapController.move(c.center, (c.zoom + delta).clamp(7.0, 11.0));
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _anim.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = _field;
    final ready = field != null && !field.isEmpty;
    return Scaffold(
      backgroundColor: _seaColor,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(35.9, 127.7),
              initialZoom: 7.1,
              minZoom: 7.0,
              maxZoom: 11,
              backgroundColor: _seaColor,
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(32.8, 125.0),
                  const LatLng(38.7, 130.2),
                ),
              ),
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              // 오프라인 폴백용 육지(타일 로드 실패 시 형태만이라도)
              if (_land.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    for (final ring in _land)
                      Polygon(
                        points: ring,
                        color: _landColor,
                        borderColor: _coastColor,
                        borderStrokeWidth: 0.8,
                      ),
                  ],
                ),
              // 밝은 베이스 지도(해안선·도로·경계) — 데이터가 위에 반투명으로 얹힌다
              TileLayer(
                urlTemplate:
                    'https://basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}@2x.png',
                userAgentPackageName: 'com.tideup.app',
                tileProvider: NetworkTileProvider(),
              ),
              // 1) 데이터 컬러 (정적 — 시각/레이어 바뀔 때만 리페인트, 지도가 비치게 반투명)
              if (ready)
                _overlay((cam) =>
                    _FillPainter(cam, field.points, _hour, _layer)),
              // 2) 바람 입자 (매 프레임 애니메이션)
              if (ready && _layer == _Layer.wind)
                _overlay((cam) => _StreakPainter(cam, _particles)),
              // 3) 도시 라벨 + 값 버블 (정적)
              if (ready)
                _overlay((cam) =>
                    _LabelPainter(cam, field.points, _hour, _layer)),
            ],
          ),

          // 좌상단: 뒤로가기
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: _RoundBtn(
                  icon: Icons.close,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),

          // 좌상단 범례 (뒤로가기 아래)
          if (ready)
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 64),
                  child: _Legend(layer: _layer),
                ),
              ),
            ),

          // 우상단: 줌 + 레이어 토글
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ZoomCluster(
                      onIn: () => _zoomBy(1),
                      onOut: () => _zoomBy(-1),
                    ),
                    const SizedBox(height: 10),
                    _LayerToggle(
                      layer: _layer,
                      onChanged: (l) => setState(() => _layer = l),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (field == null && _error == null)
            const Center(
                child: CircularProgressIndicator(color: _labelInk)),
          if (_error != null)
            const Center(
              child: Text('기상 데이터를 불러오지 못했어요',
                  style: TextStyle(color: _labelInk)),
            ),

          // 하단: 재생 바
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: _PlayBar(
                  layer: _layer,
                  times: field.times,
                  hour: _hour,
                  playing: _playing,
                  onHour: (h) => setState(() => _hour = h),
                  onPlay: _togglePlay,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// FlutterMap 좌표계를 쓰는 CustomPaint 오버레이 헬퍼.
  Widget _overlay(CustomPainter Function(MapCamera cam) build) {
    return Builder(
      builder: (ctx) {
        final cam = MapCamera.of(ctx);
        return IgnorePointer(
          child: CustomPaint(size: Size.infinite, painter: build(cam)),
        );
      },
    );
  }
}

// ── 색 스케일 ──────────────────────────────────────────
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

// 풍속(m/s) → 파랑 단색 램프 (윈디 바람맵).
const _windStops = [
  (0.0, Color(0xFFEAF3FB)),
  (3.0, Color(0xFFBBD8F1)),
  (7.0, Color(0xFF80B2E6)),
  (12.0, Color(0xFF4E86D6)),
  (20.0, Color(0xFF2C57A6)),
  (35.0, Color(0xFF16316E)),
];
Color windColor(double s) => _lerpStops(_windStops, s);

// 수온(°C) → 주황 계열 히트.
const _tempStops = [
  (10.0, Color(0xFF4C8DE0)),
  (16.0, Color(0xFF43B6B0)),
  (20.0, Color(0xFF7FC24A)),
  (24.0, Color(0xFFF2B134)),
  (28.0, Color(0xFFED6A2C)),
  (32.0, Color(0xFFD5342B)),
];
Color tempColor(double t) => _lerpStops(_tempStops, t);

// ── 입자 ───────────────────────────────────────────────
class _P {
  double lat, lon;
  double age = 0;
  int life;
  double spd = 0;
  final List<LatLng> trail = [];
  _P({required this.lat, required this.lon, required this.life});
}

bool _onScreen(Offset o, Size s, double m) =>
    o.dx > -m && o.dx < s.width + m && o.dy > -m && o.dy < s.height + m;

// ── 데이터 컬러 풀커버 ─────────────────────────────────
class _FillPainter extends CustomPainter {
  final MapCamera cam;
  final List<FieldPoint> points;
  final int hour;
  final _Layer layer;

  _FillPainter(this.cam, this.points, this.hour, this.layer);

  @override
  void paint(Canvas canvas, Size size) {
    // 격자 간격(약 0.6°)을 화면 픽셀로 환산해 블롭 반경을 정한다.
    final a = cam.latLngToScreenOffset(const LatLng(35.6, 127.0));
    final b = cam.latLngToScreenOffset(const LatLng(36.2, 127.0));
    final spacing = (a - b).distance.clamp(30.0, 200.0);
    final r = spacing * 0.85;
    final blur = spacing * 0.6;

    for (final p in points) {
      if (hour >= p.hours.length) continue;
      final h = p.hours[hour];
      final Color? c;
      if (layer == _Layer.wind) {
        final s = h.windSpeedMs;
        c = s == null ? null : windColor(s);
      } else {
        final t = h.waterTempC;
        c = t == null ? null : tempColor(t);
      }
      if (c == null) continue;
      final o = cam.latLngToScreenOffset(LatLng(p.lat, p.lon));
      if (!_onScreen(o, size, r + blur)) continue;
      canvas.drawCircle(
        o,
        r,
        Paint()
          // 반투명 — 밑의 지도(해안선·도로)가 비쳐 보이도록
          ..color = c.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }
  }

  @override
  bool shouldRepaint(_FillPainter old) =>
      old.hour != hour ||
      old.layer != layer ||
      old.cam.center != cam.center ||
      old.cam.zoom != cam.zoom;
}

// ── 바람 입자 (흰 흐름선) ──────────────────────────────
class _StreakPainter extends CustomPainter {
  final MapCamera cam;
  final List<_P> particles;
  _StreakPainter(this.cam, this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final p in particles) {
      final tr = p.trail;
      if (tr.length < 2) continue;
      final ageFade = (1.0 - (p.age / p.life)).clamp(0.0, 1.0);
      for (var i = 1; i < tr.length; i++) {
        final a = cam.latLngToScreenOffset(tr[i - 1]);
        final b = cam.latLngToScreenOffset(tr[i]);
        final head = i / (tr.length - 1);
        final alpha = (head * head * 0.85 * ageFade).clamp(0.0, 1.0);
        paint
          ..color = Colors.white.withValues(alpha: alpha)
          ..strokeWidth = 1.0 + head * 1.8;
        canvas.drawLine(a, b, paint);
      }
      final headPt = cam.latLngToScreenOffset(tr.last);
      canvas.drawCircle(headPt, 1.6,
          Paint()..color = Colors.white.withValues(alpha: 0.85 * ageFade));
    }
  }

  @override
  bool shouldRepaint(_StreakPainter old) => true;
}

// ── 도시 라벨 + 값 버블 ────────────────────────────────
class _LabelPainter extends CustomPainter {
  final MapCamera cam;
  final List<FieldPoint> points;
  final int hour;
  final _Layer layer;

  _LabelPainter(this.cam, this.points, this.hour, this.layer);

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(textDirection: TextDirection.ltr);

    void label(String text, Offset at, {bool bold = true, double size = 12.5}) {
      tp.text = TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          color: _labelInk,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          shadows: const [
            Shadow(color: Colors.white, blurRadius: 3),
            Shadow(color: Colors.white, blurRadius: 6),
          ],
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy));
    }

    void bubble(String value, Offset at, Color ring) {
      const r = 17.0;
      // 그림자 + 흰 원 + 링
      canvas.drawCircle(at, r,
          Paint()..color = Colors.black.withValues(alpha: 0.12)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(at, r, Paint()..color = Colors.white);
      canvas.drawCircle(
          at,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ring.withValues(alpha: 0.9));
      tp.text = TextSpan(
        text: value,
        style: const TextStyle(
          fontFamily: fontFamily,
          color: _labelInk,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
    }

    if (layer == _Layer.wind) {
      for (final c in _cities) {
        final o = cam.latLngToScreenOffset(LatLng(c.$2, c.$3));
        if (!_onScreen(o, size, 40)) continue;
        if (c.$4) {
          final w = interpolateWind(points, hour, c.$2, c.$3);
          final spd = (w?.$1 ?? 0).round();
          bubble('$spd', o, windColor((w?.$1 ?? 0)));
          label(c.$1, Offset(o.dx, o.dy + 20), bold: false, size: 11.5);
        } else {
          label(c.$1, Offset(o.dx, o.dy - 7), bold: false, size: 11);
        }
      }
    } else {
      // 수온: 도시 이름 라벨 + 해상 격자점 값 버블
      for (final c in _cities) {
        final o = cam.latLngToScreenOffset(LatLng(c.$2, c.$3));
        if (!_onScreen(o, size, 40)) continue;
        label(c.$1, Offset(o.dx, o.dy - 7), bold: false, size: 11);
      }
      for (var i = 0; i < points.length; i++) {
        final p = points[i];
        if (hour >= p.hours.length) continue;
        final t = p.hours[hour].waterTempC;
        if (t == null) continue;
        if (i % 2 != 0) continue; // 밀도 줄이기
        final o = cam.latLngToScreenOffset(LatLng(p.lat, p.lon));
        if (!_onScreen(o, size, 40)) continue;
        bubble('${t.round()}°', o, tempColor(t));
      }
    }
  }

  @override
  bool shouldRepaint(_LabelPainter old) =>
      old.hour != hour ||
      old.layer != layer ||
      old.cam.center != cam.center ||
      old.cam.zoom != cam.zoom;
}

// ── 컨트롤 위젯 ────────────────────────────────────────
class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: _labelInk, size: 20),
        ),
      ),
    );
  }
}

class _ZoomCluster extends StatelessWidget {
  final VoidCallback onIn;
  final VoidCallback onOut;
  const _ZoomCluster({required this.onIn, required this.onOut});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 40,
            child: Icon(icon, color: _labelInk, size: 20),
          ),
        );
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: Colors.black26,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove, onOut),
          Container(width: 1, height: 22, color: Colors.black12),
          btn(Icons.add, onIn),
        ],
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
    Widget pill(_Layer l, IconData icon, String text) {
      final sel = layer == l;
      return GestureDetector(
        onTap: () => onChanged(l),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _labelInk : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: sel ? Colors.white : _labelInk),
              const SizedBox(width: 5),
              Text(text,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    color: sel ? Colors.white : _labelInk,
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
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
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

class _Legend extends StatelessWidget {
  final _Layer layer;
  const _Legend({required this.layer});

  @override
  Widget build(BuildContext context) {
    final wind = layer == _Layer.wind;
    final title = wind ? '바람 (m/s)' : '수온 (°C)';
    // 위(높음)→아래(낮음) 그라데이션 + 눈금
    final stops = wind
        ? [windColor(35), windColor(22), windColor(12), windColor(5), windColor(0)]
        : [tempColor(30), tempColor(26), tempColor(22), tempColor(16), tempColor(10)];
    final ticks = wind ? ['35', '25', '15', '5', '0'] : ['30', '25', '20', '15', '10'];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(
                fontFamily: fontFamily,
                color: _labelInk,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 12,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: stops,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 160,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final t in ticks)
                      Text(t,
                          style: const TextStyle(
                            fontFamily: fontFamily,
                            color: _labelInk,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          )),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayBar extends StatelessWidget {
  final _Layer layer;
  final List<DateTime> times;
  final int hour;
  final bool playing;
  final ValueChanged<int> onHour;
  final VoidCallback onPlay;

  const _PlayBar({
    required this.layer,
    required this.times,
    required this.hour,
    required this.playing,
    required this.onHour,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final t = hour < times.length ? times[hour] : DateTime.now();
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy년 M월 d일 EEEE', 'ko_KR').format(t);
    final maxIdx = (times.length - 1).clamp(0, 47);

    // 시간축 눈금 (5개) — 현재 실시각과 같으면 '지금'.
    final tickIdx = <int>[
      0,
      (maxIdx * 0.25).round(),
      (maxIdx * 0.5).round(),
      (maxIdx * 0.75).round(),
      maxIdx,
    ];
    Widget tick(int i) {
      final tt = i < times.length ? times[i] : now;
      final isNow = tt.year == now.year &&
          tt.month == now.month &&
          tt.day == now.day &&
          tt.hour == now.hour;
      return Text(
        isNow ? '지금' : DateFormat('a h시', 'ko_KR').format(tt),
        style: TextStyle(
          fontFamily: fontFamily,
          color: isNow ? _labelInk : _labelInk.withValues(alpha: 0.55),
          fontSize: 10.5,
          fontWeight: isNow ? FontWeight.w700 : FontWeight.w500,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(6, 8, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(radiusXl),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onPlay,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _labelInk,
                shape: BoxShape.circle,
              ),
              child: Icon(playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(layer == _Layer.wind ? '풍속' : '수온',
                    style: const TextStyle(
                      fontFamily: fontFamily,
                      color: _labelInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )),
                Text(dateStr,
                    style: TextStyle(
                      fontFamily: fontFamily,
                      color: _labelInk.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    )),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: _labelInk,
                    inactiveTrackColor: Colors.black12,
                    thumbColor: _labelInk,
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 13),
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: hour.toDouble().clamp(0, maxIdx.toDouble()),
                    min: 0,
                    max: maxIdx.toDouble(),
                    onChanged: (v) => onHour(v.round()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [for (final i in tickIdx) tick(i)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
