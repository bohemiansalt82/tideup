import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/models.dart';
import '../theme.dart';

// ── 공유 레이아웃 상수 (차트와 왼쪽 라벨 열이 함께 쓴다) ──
const _pxPerHour = 48.0;
const _chartTop = 30.0; // 만조/간조 라벨·현재 툴팁 공간
const _chartH = 130.0; // 조위 계단 곡선 영역
const _axisH = 16.0; // 시간 라벨
const _laneWeatherH = 28.0; // 날씨 이모지
const _laneWindH = 40.0; // 풍향 화살표 + 풍속
const _laneWaveH = 24.0; // 파고
const _laneFlowH = 28.0; // 물흐름 퍼센트
const _laneTempH = 22.0; // 수온
const _totalH = _chartTop +
    _chartH +
    _axisH +
    _laneWeatherH +
    _laneWindH +
    _laneWaveH +
    _laneFlowH +
    _laneTempH;

/// 밀물(상승) 파랑 / 썰물(하강) 빨강.
const _risingColor = reportBlue;
const _fallingColor = reportOrange;

// 날씨 아이콘 색 (일반적인 날씨앱 관례색)
const _sunColor = Color(0xFFF6A609); // 해 — 앰버
const _moonColor = Color(0xFF6C79C7); // 달 — 남색
const _cloudColor = Color(0xFF9AA3AD); // 구름 — 회색
const _fogColor = Color(0xFFB3BCC4); // 안개
const _rainColor = Color(0xFF4A9FE0); // 비 — 파랑
const _snowColor = Color(0xFF7EC8F0); // 눈 — 하늘색
const _thunderColor = Color(0xFFF08C1A); // 뇌우 — 주황

/// WMO weather code → (Material 아이콘, 색) — 캔버스 드로잉용.
(IconData, Color) _weatherIcon(int code, {bool night = false}) {
  if (code == 0) {
    return night
        ? (Icons.nightlight_round, _moonColor)
        : (Icons.wb_sunny, _sunColor);
  }
  if (code <= 2) {
    return night
        ? (Icons.nights_stay, _moonColor)
        : (Icons.wb_cloudy, _cloudColor);
  }
  if (code == 3) return (Icons.cloud, _cloudColor);
  if (code <= 49) return (Icons.blur_on, _fogColor); // 안개
  if (code <= 69) return (Icons.water_drop, _rainColor); // 비
  if (code <= 79) return (Icons.ac_unit, _snowColor); // 눈
  if (code <= 84) return (Icons.water_drop, _rainColor);
  if (code <= 94) return (Icons.ac_unit, _snowColor);
  return (Icons.flash_on, _thunderColor); // 뇌우
}

/// 하루 조위 계단식(step) 차트 + 시간대별 시리즈 레인.
///
/// 위에서부터: 조위 계단 곡선(밀물 파랑/썰물 빨강, fill 포함) → 시간축 →
/// 날씨 → 바람(풍향·풍속) → 물흐름(조위 변화율) → 수온.
/// 전체가 1시간 = 48px로 좌우 스크롤되고, 왼쪽 라벨 열은 고정된다.
class TideChart extends StatefulWidget {
  final List<TidePoint> curve;
  final List<TideEvent> events;
  final List<HourlyWeather> hourly;

  const TideChart({
    super.key,
    required this.curve,
    required this.events,
    this.hourly = const [],
  });

  @override
  State<TideChart> createState() => _TideChartState();
}

class _TideChartState extends State<TideChart> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 첫 프레임 후 현재 시각이 화면 중앙에 오도록 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || widget.curve.isEmpty) return;
      final start = widget.curve.first.time;
      final now = DateTime.now();
      final nowX = now.difference(start).inMinutes / 60.0 * _pxPerHour;
      final viewport = _scrollController.position.viewportDimension;
      final target = (nowX - viewport / 2)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _laneLabel(String text, double height) {
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: caption.copyWith(
                color: inkMuted, fontSize: 10, fontWeight: FontWeight.w500)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.curve.length < 2) {
      return const SizedBox(
        height: 140,
        child: Center(
          child:
              Text('조위 곡선 데이터 없음', style: TextStyle(color: inkTertiary)),
        ),
      );
    }
    final start = widget.curve.first.time;
    final end = widget.curve.last.time;
    final hours = end.difference(start).inMinutes / 60.0;
    final width = hours * _pxPerHour + 16;

    return SizedBox(
      height: _totalH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 고정 라벨 열
          SizedBox(
            width: 38,
            child: Column(
              children: [
                _laneLabel('조위', _chartTop + _chartH + _axisH),
                _laneLabel('날씨', _laneWeatherH),
                _laneLabel('바람', _laneWindH),
                _laneLabel('파고', _laneWaveH),
                _laneLabel('물흐름', _laneFlowH),
                _laneLabel('수온', _laneTempH),
              ],
            ),
          ),
          // 스크롤 차트
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: PointerDeviceKind.values.toSet(),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: _totalH,
                  child: CustomPaint(
                    painter: _TideStepPainter(
                      curve: widget.curve,
                      events: widget.events,
                      hourly: widget.hourly,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TideStepPainter extends CustomPainter {
  final List<TidePoint> curve;
  final List<TideEvent> events;
  final List<HourlyWeather> hourly;

  _TideStepPainter({
    required this.curve,
    required this.events,
    required this.hourly,
  });

  /// 1시간 간격 버킷팅 — 각 시각의 첫 샘플을 대표값으로 쓴다.
  List<TidePoint> _hourlySteps() {
    final out = <TidePoint>[];
    int? lastHourKey;
    for (final p in curve) {
      final key = p.time.day * 100 + p.time.hour;
      if (key != lastHourKey) {
        out.add(p);
        lastHourKey = key;
      }
    }
    if (out.isNotEmpty && out.last.time != curve.last.time) {
      out.add(curve.last);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const sidePad = 8.0;
    final chartW = size.width - sidePad * 2;
    final chartBottom = _chartTop + _chartH;

    final steps = _hourlySteps();
    final t0 = steps.first.time.millisecondsSinceEpoch.toDouble();
    final t1 = steps.last.time.millisecondsSinceEpoch.toDouble();
    var minL = steps.first.levelCm, maxL = steps.first.levelCm;
    for (final p in steps) {
      if (p.levelCm < minL) minL = p.levelCm;
      if (p.levelCm > maxL) maxL = p.levelCm;
    }
    final range = (maxL - minL).abs() < 1 ? 1 : maxL - minL;

    double toX(DateTime t) =>
        sidePad + (t.millisecondsSinceEpoch - t0) / (t1 - t0) * chartW;
    double toY(double level) =>
        _chartTop + (1 - (level - minL) / range) * _chartH * 0.92;

    final tp = TextPainter(textDirection: TextDirection.ltr);

    // 레인 경계 y 좌표
    final laneWeatherTop = chartBottom + _axisH;
    final laneWindTop = laneWeatherTop + _laneWeatherH;
    final laneWaveTop = laneWindTop + _laneWindH;
    final laneFlowTop = laneWaveTop + _laneWaveH;
    final laneTempTop = laneFlowTop + _laneFlowH;

    // 시간별 데이터 매핑 (일·시 → HourlyWeather)
    final hourlyByKey = <int, HourlyWeather>{
      for (final h in hourly) h.time.day * 100 + h.time.hour: h,
    };

    // 시간 눈금선 + 시간 라벨
    final totalHours = ((t1 - t0) / Duration.millisecondsPerHour).round();
    for (var h = 0; h <= totalHours; h++) {
      final t = steps.first.time.add(Duration(hours: h));
      if (t.millisecondsSinceEpoch > t1 + 1) continue;
      final x = toX(t);
      canvas.drawLine(
        Offset(x, _chartTop - 4),
        Offset(x, laneTempTop + _laneTempH - 4),
        Paint()
          ..color = hairlineSoft
          ..strokeWidth = 1,
      );
      tp.text = TextSpan(
        text: '${t.hour}시',
        style: const TextStyle(
            fontFamily: fontFamily, color: inkTertiary, fontSize: 10),
      );
      tp.layout();
      // 눈금선 위가 아니라 셀(컬럼) 가운데에 — 아래 레인 값들과 정렬
      tp.paint(
          canvas,
          Offset((x + _pxPerHour / 2 - tp.width / 2)
              .clamp(0, size.width - tp.width),
              chartBottom + 2));
    }

    // 레인 구분 가로선
    for (final y in [
      chartBottom + _axisH,
      laneWindTop,
      laneWaveTop,
      laneFlowTop,
      laneTempTop
    ]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          Paint()..color = hairlineSoft);
    }

    // ── 조위: 구간별 fill + 계단 라인 ──
    for (var i = 1; i < steps.length; i++) {
      final prev = steps[i - 1], cur = steps[i];
      final rising = cur.levelCm >= prev.levelCm;
      final color = rising ? _risingColor : _fallingColor;
      final x0 = toX(prev.time), x1 = toX(cur.time);
      final yPrev = toY(prev.levelCm);
      canvas.drawRect(
        Rect.fromLTRB(x0, yPrev, x1, chartBottom),
        Paint()..color = color.withValues(alpha: 0.16),
      );
      final seg = Path()
        ..moveTo(x0, yPrev)
        ..lineTo(x1, yPrev)
        ..lineTo(x1, toY(cur.levelCm));
      canvas.drawPath(
        seg,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // ── 만조/간조 점 + 라벨 ──
    final fmt = DateFormat('HH:mm');
    for (final e in events) {
      if (e.time.isBefore(steps.first.time) ||
          e.time.isAfter(steps.last.time)) {
        continue;
      }
      final o = Offset(toX(e.time), toY(e.levelCm));
      final dotColor = e.isHigh ? _risingColor : _fallingColor;
      canvas.drawCircle(o, 4, Paint()..color = dotColor);
      canvas.drawCircle(
          o,
          4,
          Paint()
            ..color = surface1
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      tp.text = TextSpan(
        text:
            '${e.isHigh ? "만조" : "간조"} ${fmt.format(e.time)} · ${e.levelCm.round()}cm',
        style: const TextStyle(
          fontFamily: fontFamily,
          color: inkMuted,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      );
      tp.layout();
      final labelY = e.isHigh ? o.dy - 18 : o.dy + 8;
      tp.paint(
          canvas,
          Offset((o.dx - tp.width / 2).clamp(0, size.width - tp.width),
              labelY.clamp(0, chartBottom - 12)));
    }

    // ── 레인: 시간 슬롯별 날씨·바람·물흐름·수온 ──
    for (var i = 0; i < steps.length - 1; i++) {
      final t = steps[i].time;
      final xCenter = toX(t) + _pxPerHour / 2;
      final h = hourlyByKey[t.day * 100 + t.hour];

      // 날씨 아이콘 (번들된 MaterialIcons — 이모지는 웹 캔버스에서 폰트
      // 로딩이 늦어 □로 보일 수 있다)
      if (h != null && h.weatherCode != null) {
        final night = t.hour < 6 || t.hour >= 20;
        final (icon, iconColor) = _weatherIcon(h.weatherCode!, night: night);
        tp.text = TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            fontSize: 15,
            color: iconColor,
          ),
        );
        tp.layout();
        tp.paint(
            canvas,
            Offset(xCenter - tp.width / 2,
                laneWeatherTop + (_laneWeatherH - tp.height) / 2));
      }

      // 바람: 화살표(바람이 가는 방향) + 풍속
      if (h != null && h.windSpeedMs != null) {
        if (h.windDirDeg != null) {
          final angle = (h.windDirDeg! + 180) * math.pi / 180;
          canvas.save();
          canvas.translate(xCenter, laneWindTop + 12);
          canvas.rotate(angle);
          final arrow = Paint()
            ..color = inkMuted
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(const Offset(0, 5), const Offset(0, -5), arrow);
          canvas.drawLine(const Offset(0, -5), const Offset(-3, -1), arrow);
          canvas.drawLine(const Offset(0, -5), const Offset(3, -1), arrow);
          canvas.restore();
        }
        tp.text = TextSpan(
          text: h.windSpeedMs!.toStringAsFixed(0),
          style: const TextStyle(
              fontFamily: fontFamily,
              color: inkMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500),
        );
        tp.layout();
        tp.paint(canvas, Offset(xCenter - tp.width / 2, laneWindTop + 22));
      }

      // 파고: 0.5~1.0m(갯바위 적정)만 녹색 배경
      if (h != null && h.waveHeightM != null) {
        final wave = h.waveHeightM!;
        if (wave >= 0.5 && wave <= 1.0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(xCenter, laneWaveTop + _laneWaveH / 2),
                width: _pxPerHour - 6,
                height: _laneWaveH - 6,
              ),
              const Radius.circular(radiusXs),
            ),
            Paint()..color = goodHighlight.withValues(alpha: 0.28),
          );
        }
        tp.text = TextSpan(
          text: '${wave.toStringAsFixed(1)}m',
          style: const TextStyle(
              fontFamily: fontFamily, color: inkMuted, fontSize: 9.5),
        );
        tp.layout();
        tp.paint(
            canvas,
            Offset(xCenter - tp.width / 2,
                laneWaveTop + (_laneWaveH - tp.height) / 2));
      }

      // 물흐름: 조위 변화율 퍼센트 (하루 중 최대 흐름 = 100%,
      // 색은 밀물 파랑/썰물 빨강)
      final delta = steps[i + 1].levelCm - steps[i].levelCm;
      final maxDelta = () {
        var m = 1.0;
        for (var j = 0; j < steps.length - 1; j++) {
          final d = (steps[j + 1].levelCm - steps[j].levelCm).abs();
          if (d > m) m = d;
        }
        return m;
      }();
      final flowPct = (delta.abs() / maxDelta * 100).round();
      // 30~70% = 낚시하기 좋은 물흐름 (골든타임) → 녹색 배경
      if (flowPct >= 30 && flowPct <= 70) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(xCenter, laneFlowTop + _laneFlowH / 2),
              width: _pxPerHour - 6,
              height: _laneFlowH - 6,
            ),
            const Radius.circular(radiusXs),
          ),
          Paint()..color = reportGreen.withValues(alpha: 0.22),
        );
      }
      tp.text = TextSpan(
        text: '$flowPct%',
        style: TextStyle(
          fontFamily: fontFamily,
          color: delta >= 0 ? _risingColor : _fallingColor,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      );
      tp.layout();
      tp.paint(
          canvas,
          Offset(xCenter - tp.width / 2,
              laneFlowTop + (_laneFlowH - tp.height) / 2));

      // 수온
      if (h != null && h.waterTempC != null) {
        tp.text = TextSpan(
          text: '${h.waterTempC!.toStringAsFixed(1)}°',
          style: const TextStyle(
              fontFamily: fontFamily, color: inkMuted, fontSize: 9.5),
        );
        tp.layout();
        tp.paint(canvas,
            Offset(xCenter - tp.width / 2, laneTempTop + (_laneTempH - tp.height) / 2));
      }
    }

    // ── 현재 시각 인디케이터 — 세로선 + 점 + "현재" 툴팁 ──
    final now = DateTime.now();
    if (now.millisecondsSinceEpoch >= t0 && now.millisecondsSinceEpoch <= t1) {
      double nowLevel = steps.last.levelCm;
      for (var i = 1; i < steps.length; i++) {
        if (steps[i].time.isAfter(now)) {
          nowLevel = steps[i - 1].levelCm;
          break;
        }
      }
      final x = toX(now);
      // 조위 라인 차트 영역까지만 (아래 레인들은 관통하지 않음)
      canvas.drawLine(
        Offset(x, _chartTop - 6),
        Offset(x, chartBottom),
        Paint()
          ..color = ink.withValues(alpha: 0.55)
          ..strokeWidth = 1.2,
      );
      final o = Offset(x, toY(nowLevel));
      canvas.drawCircle(o, 6, Paint()..color = ink);
      canvas.drawCircle(
          o,
          6,
          Paint()
            ..color = surface1
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);

      tp.text = const TextSpan(
        text: '현재',
        style: TextStyle(
          fontFamily: fontFamily,
          color: onPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      );
      tp.layout();
      const chipPadH = 7.0, chipPadV = 4.0;
      final chipW = tp.width + chipPadH * 2;
      final chipH = tp.height + chipPadV * 2;
      final chipX = (x - chipW / 2).clamp(2.0, size.width - chipW - 2.0);
      const chipY = 2.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(chipX, chipY, chipW, chipH),
          const Radius.circular(radiusXs),
        ),
        Paint()..color = ink,
      );
      final tail = Path()
        ..moveTo(x - 4, chipY + chipH)
        ..lineTo(x + 4, chipY + chipH)
        ..lineTo(x, chipY + chipH + 5)
        ..close();
      canvas.drawPath(tail, Paint()..color = ink);
      tp.paint(canvas, Offset(chipX + chipPadH, chipY + chipPadV));
    }
  }

  @override
  bool shouldRepaint(_TideStepPainter oldDelegate) =>
      oldDelegate.curve != curve ||
      oldDelegate.events != events ||
      oldDelegate.hourly != hourly;
}
