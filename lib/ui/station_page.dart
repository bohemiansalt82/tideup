import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../logic/fishing_score.dart';
import '../logic/multtae.dart';
import '../logic/sun_moon.dart';
import '../models/models.dart';
import '../services/notifications.dart';
import '../services/repository.dart';
import 'theme.dart';
import 'widgets/glass_card.dart';
import 'widgets/nearby_map.dart';
import 'widgets/place_actions.dart';
import 'widgets/tide_chart.dart';

/// 한 지점의 상세 화면 — 크림 캔버스 위 흰색 카드 구성 (DESIGN.md).
/// 메인 리스트에서 지점을 탭하면 이 화면으로 들어온다.
class StationPage extends StatefulWidget {
  final Repository repository;
  final Station station;

  const StationPage({
    super.key,
    required this.repository,
    required this.station,
  });

  @override
  State<StationPage> createState() => _StationPageState();
}

class _StationPageState extends State<StationPage> {
  StationDayData? _data;
  NearbyInfo? _nearby;
  Object? _error;
  bool _notifyOn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      final data = await widget.repository
          .loadStationData(widget.station, refresh: refresh);
      if (mounted) setState(() => _data = data);
      // 알림이 켜져 있으면 최신 예보로 다시 예약
      final on = await TideNotifications.isEnabled(widget.station.id);
      if (mounted) setState(() => _notifyOn = on);
      if (on) {
        await TideNotifications.scheduleFor(widget.station, data.tideEvents);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    // 주변 편의시설은 별도 로드 (실패해도 본 화면에는 영향 없음)
    final nearby = await widget.repository.loadNearby(widget.station);
    if (mounted && nearby != null) setState(() => _nearby = nearby);
  }

  Future<void> _toggleNotify() async {
    final data = _data;
    if (data == null) return;
    final result = await TideNotifications.setEnabled(
        widget.station, data.tideEvents, !_notifyOn);
    if (mounted) {
      setState(() => _notifyOn = result);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result
            ? '만조·간조 1시간 전에 알려드릴게요'
            : '알림을 껐어요'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final data = _data;
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: () {
        setState(() => _error = null);
        _load(refresh: true);
      });
    }
    if (data == null) {
      return const Center(child: CircularProgressIndicator(color: ink));
    }

    final now = DateTime.now();
    final st = data.station;
    final system = systemForLocation(st.lat, st.lon);
    final multae = multaeFor(now, system);
    final sun = sunTimesFor(now, st.lat, st.lon);
    final age = moonAge(now);
    final index = fishingIndexFor(
        multae: multae, now: data.now, hourly: data.hourly);

    // 다음 만조/간조
    final upcoming =
        data.tideEvents.where((e) => e.time.isAfter(now)).toList();
    final next = upcoming.isEmpty ? null : upcoming.first;

    // 밀물/썰물 판별: 다음 이벤트가 만조면 지금은 밀물
    final rising = next?.isHigh ?? true;

    return RefreshIndicator(
      color: ink,
      backgroundColor: surface1,
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _Header(
            station: st,
            multae: multae,
            rising: rising,
            next: next,
            isMock: data.isMock,
            refStationName:
                st.isPlace ? widget.repository.stationNameOf(st.code) : null,
          ),
          const SizedBox(height: 32),
          GlassCard(
            title: '오늘 조위',
            icon: Icons.water,
            mockup: true,
            padding: const EdgeInsets.all(16),
            child: TideChart(
              curve: data.tideCurve,
              events: data.tideEvents,
              hourly: data.hourly,
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            title: '만조 · 간조',
            icon: Icons.swap_vert,
            trailing: kIsWeb
                ? null
                : InkWell(
                    onTap: _toggleNotify,
                    borderRadius: BorderRadius.circular(radiusXs),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _notifyOn
                                ? Icons.notifications_active
                                : Icons.notifications_none,
                            size: 17,
                            color: _notifyOn ? finOrange : inkSubtle,
                          ),
                          const SizedBox(width: 3),
                          Text('1시간 전 알림',
                              style: caption.copyWith(
                                  color: _notifyOn ? ink : inkSubtle,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
            child: _TideEventList(events: data.tideEvents),
          ),
          const SizedBox(height: 12),
          GlassCard(
            title: '주간 물때',
            icon: Icons.calendar_month,
            child: _WeekCard(repository: widget.repository, station: st),
          ),
          const SizedBox(height: 12),
          GlassCard(
            title: '낚시 지수',
            icon: Icons.phishing,
            child: data.fishing != null
                ? _OfficialFishingCard(forecast: data.fishing!)
                : _FishingCard(index: index),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GlassCard(
                    title: '바람',
                    icon: Icons.air,
                    padding: const EdgeInsets.all(20),
                    child: _WindCard(now: data.now),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassCard(
                    title: '바다',
                    icon: Icons.waves,
                    padding: const EdgeInsets.all(20),
                    child: _SeaCard(now: data.now),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GlassCard(
                    title: '일출 · 일몰',
                    icon: Icons.wb_twilight,
                    padding: const EdgeInsets.all(20),
                    child: _SunCard(sun: sun),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassCard(
                    title: '달 · 음력',
                    icon: Icons.nightlight_round,
                    padding: const EdgeInsets.all(20),
                    child: _MoonCard(age: age, multae: multae),
                  ),
                ),
              ],
            ),
          ),
          if (_nearby != null) ...[
            const SizedBox(height: 12),
            GlassCard(
              title: '주변 5km',
              icon: Icons.place_outlined,
              mockup: true,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NearbyMap(
                    station: st,
                    info: _nearby!,
                    windSpeedMs: data.now.windSpeedMs,
                    windDirDeg: data.now.windDirDeg,
                  ),
                  const SizedBox(height: 12),
                  _NearbyCard(info: _nearby!, stationName: st.name),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${data.isMock ? '샘플 데이터 표시 중 — assets/config/api_keys.json에 인증키를 넣으면 실제 예보가 표시됩니다' : '자료: 국립해양조사원 조석예보 · 기상 데이터'}'
              '${data.fetchedAt != null ? '\n${_fetchedAtText(data.fetchedAt!)} 기준' : ''}',
              textAlign: TextAlign.center,
              style: caption.copyWith(color: inkTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 데이터 기준 시각 — 오늘이면 시각만, 아니면 날짜 포함 (오프라인 캐시 표시).
String _fetchedAtText(DateTime t) {
  final now = DateTime.now();
  final sameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay
      ? DateFormat('HH:mm').format(t)
      : DateFormat('M/d HH:mm').format(t);
}

/// 사리·조금 중 더 가까운 쪽의 D-day 표기.
String _cycleDday(Multae m) {
  final sari = m.daysToSari;
  final jogeum = m.daysToJogeum;
  if (sari == 0) return '오늘 사리';
  if (jogeum == 0) return '오늘 조금';
  return sari <= jogeum ? '사리 D-$sari' : '조금 D-$jogeum';
}

class _Header extends StatelessWidget {
  final Station station;
  final Multae multae;
  final bool rising;
  final TideEvent? next;
  final bool isMock;
  final String? refStationName; // 장소일 때 조석 기준 관측소 이름

  const _Header({
    required this.station,
    required this.multae,
    required this.rising,
    required this.next,
    required this.isMock,
    this.refStationName,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm');
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(station.name, style: headline),
            if (isMock) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: surface2,
                  borderRadius: BorderRadius.circular(radiusXs),
                ),
                child: Text('샘플', style: caption.copyWith(color: inkMuted)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // 히어로 — 오늘의 물때를 display-xl로
        Text(multae.label, style: displayXl),
        const SizedBox(height: 8),
        Text(
          '${rising ? "밀물" : "썰물"} ${rising ? "▲" : "▼"}'
          '${next != null ? '  ·  다음 ${next!.isHigh ? "만조" : "간조"} ${fmt.format(next!.time)}' : ''}',
          style: bodyLg,
        ),
        const SizedBox(height: 4),
        Text(
          '음력 ${multae.lunarMonth}월 ${multae.lunarDay}일 · '
          '${multae.system == MultaeSystem.west7 ? "7물때식" : "8물때식"} · '
          '${_cycleDday(multae)}',
          style: bodySm.copyWith(color: inkMuted),
        ),
        if (refStationName != null) ...[
          const SizedBox(height: 2),
          Text(
            '조석 기준: $refStationName 관측소',
            style: caption.copyWith(color: inkSubtle),
          ),
        ],
      ],
    );
  }
}

class _TideEventList extends StatelessWidget {
  final List<TideEvent> events;

  const _TideEventList({required this.events});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final shown = events
        .where((e) => e.time.isAfter(today))
        .take(8)
        .toList();
    if (shown.isEmpty) {
      return Text('예보 없음', style: body.copyWith(color: inkTertiary));
    }
    final timeFmt = DateFormat('HH:mm');
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const Divider(color: hairlineSoft, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Icon(
                  shown[i].isHigh
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 16,
                  color: shown[i].isHigh ? reportBlue : reportOrange,
                ),
                const SizedBox(width: 10),
                Text(
                  shown[i].isHigh ? '만조' : '간조',
                  style: bodySm.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 10),
                Text(
                  shown[i].time.day == now.day ? '오늘' : '내일',
                  style: caption.copyWith(color: inkSubtle),
                ),
                const Spacer(),
                Text(
                  timeFmt.format(shown[i].time),
                  style: body.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 58,
                  child: Text(
                    '${shown[i].levelCm.round()}cm',
                    textAlign: TextAlign.right,
                    style: bodySm.copyWith(color: inkMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 주간(7일) 물때·만조/간조 표.
class _WeekCard extends StatelessWidget {
  final Repository repository;
  final Station station;

  const _WeekCard({required this.repository, required this.station});

  @override
  Widget build(BuildContext context) {
    final system = systemForLocation(station.lat, station.lon);
    final timeFmt = DateFormat('HH:mm');
    return FutureBuilder<List<(DateTime, List<TideEvent>)>>(
      future: repository.loadWeek(station),
      builder: (context, snap) {
        final week = snap.data;
        if (week == null) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: inkSubtle, strokeWidth: 2),
              ),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < week.length; i++) ...[
              if (i > 0) const Divider(color: hairlineSoft, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 58,
                      child: Text(
                        i == 0
                            ? '오늘'
                            : '${week[i].$1.month}/${week[i].$1.day} (${DateFormat.E('ko_KR').format(week[i].$1)})',
                        style: caption.copyWith(
                            color: i == 0 ? ink : inkMuted,
                            fontWeight:
                                i == 0 ? FontWeight.w600 : FontWeight.w400),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        multaeFor(week[i].$1, system).label,
                        style: bodySm.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _eventLine(true, week[i].$2, timeFmt),
                          const SizedBox(height: 1),
                          _eventLine(false, week[i].$2, timeFmt),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _eventLine(bool high, List<TideEvent> events, DateFormat fmt) {
    final list = events.where((e) => e.isHigh == high).toList();
    return Row(
      children: [
        Icon(high ? Icons.arrow_upward : Icons.arrow_downward,
            size: 11, color: high ? reportBlue : reportOrange),
        const SizedBox(width: 4),
        Text(
          list.isEmpty ? '-' : list.map((e) => fmt.format(e.time)).join('  '),
          style: caption.copyWith(
            color: inkMuted,
            fontSize: 11,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 공식 바다낚시지수 등급 → 표시 색 (분석 표면이므로 리포트 팔레트).
Color _gradeColor(String? grade) {
  switch (grade) {
    case '매우좋음':
    case '좋음':
      return reportGreen;
    case '보통':
      return reportBlue;
    case '나쁨':
      return reportOrange;
    case '매우나쁨':
      return semanticError;
    default:
      return inkTertiary;
  }
}

/// 국립해양조사원 공식 바다낚시지수 카드 — 인근 포인트의 어종별 오전/오후 등급.
class _OfficialFishingCard extends StatelessWidget {
  final FishingForecast forecast;

  const _OfficialFishingCard({required this.forecast});

  Widget _grade(String? g) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration:
              BoxDecoration(shape: BoxShape.circle, color: _gradeColor(g)),
        ),
        const SizedBox(width: 5),
        Text(g ?? '-', style: bodySm),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                '${forecast.pointName} 포인트',
                style: cardTitle.copyWith(fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (forecast.tidePhase != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: surface2,
                  borderRadius: BorderRadius.circular(radiusXs),
                ),
                child: Text(forecast.tidePhase!,
                    style: caption.copyWith(color: inkMuted, fontSize: 11)),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '지점에서 ${forecast.distanceKm < 10 ? forecast.distanceKm.toStringAsFixed(1) : forecast.distanceKm.round()}km · 국립해양조사원 예보',
          style: caption.copyWith(color: inkSubtle),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(flex: 4, child: SizedBox()),
            Expanded(
                flex: 3,
                child: Text('오전',
                    style: caption.copyWith(
                        color: inkMuted, fontWeight: FontWeight.w500))),
            Expanded(
                flex: 3,
                child: Text('오후',
                    style: caption.copyWith(
                        color: inkMuted, fontWeight: FontWeight.w500))),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < forecast.species.length; i++) ...[
          if (i > 0) const Divider(color: hairlineSoft, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(forecast.species[i].species,
                      style: bodySm.copyWith(fontWeight: FontWeight.w500)),
                ),
                Expanded(flex: 3, child: _grade(forecast.species[i].morning)),
                Expanded(
                    flex: 3, child: _grade(forecast.species[i].afternoon)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FishingCard extends StatelessWidget {
  final FishingIndex index;

  const _FishingCard({required this.index});

  @override
  Widget build(BuildContext context) {
    // Fin 오렌지는 이 카드(낚시 지수 = 이 앱의 "Fin")에만 쓴다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${index.score}',
              style: displayMd.copyWith(color: finOrange),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(index.grade,
                  style: cardTitle.copyWith(fontSize: 18)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(radiusXs),
          child: LinearProgressIndicator(
            value: index.score / 100,
            minHeight: 6,
            backgroundColor: surface2,
            valueColor: const AlwaysStoppedAnimation(finOrange),
          ),
        ),
        const SizedBox(height: 14),
        for (final r in index.reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $r', style: bodySm.copyWith(color: inkMuted)),
          ),
      ],
    );
  }
}

class _WindCard extends StatelessWidget {
  final MarineNow now;

  const _WindCard({required this.now});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (now.windDirDeg != null)
          Transform.rotate(
            // 풍향은 불어오는 방향 → 화살표는 바람이 가는 방향으로
            angle: (now.windDirDeg! + 180) * 3.14159 / 180,
            child: const Icon(Icons.navigation, color: ink, size: 28),
          )
        else
          const Icon(Icons.air, color: inkTertiary, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                now.windSpeedMs != null
                    ? '${now.windSpeedMs!.toStringAsFixed(1)} m/s'
                    : '-',
                style: cardTitle.copyWith(fontSize: 20),
              ),
              Text('${windDirText(now.windDirDeg)}풍',
                  style: bodySm.copyWith(color: inkMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeaCard extends StatelessWidget {
  final MarineNow now;

  const _SeaCard({required this.now});

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: bodySm.copyWith(color: inkMuted)),
              Text(value,
                  style: bodySm.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
        );
    return Column(
      children: [
        row('수온',
            now.waterTempC != null ? '${now.waterTempC!.toStringAsFixed(1)}°' : '-'),
        row('파고',
            now.waveHeightM != null ? '${now.waveHeightM!.toStringAsFixed(1)}m' : '-'),
        row('기온',
            now.airTempC != null ? '${now.airTempC!.round()}°' : '-'),
      ],
    );
  }
}

class _SunCard extends StatelessWidget {
  final SunTimes sun;

  const _SunCard({required this.sun});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sun.sunrise != null ? fmt.format(sun.sunrise!) : '-',
          style: cardTitle,
        ),
        Text('일출', style: caption.copyWith(color: inkSubtle)),
        const SizedBox(height: 10),
        Text(
          '일몰 ${sun.sunset != null ? fmt.format(sun.sunset!) : '-'}',
          style: bodySm.copyWith(color: inkMuted),
        ),
      ],
    );
  }
}

class _MoonCard extends StatelessWidget {
  final double age;
  final Multae multae;

  const _MoonCard({required this.age, required this.multae});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(moonPhaseEmoji(age), style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                moonPhaseName(age),
                style: bodySm.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '음력 ${multae.lunarMonth}월 ${multae.lunarDay}일\n월령 ${age.toStringAsFixed(1)}일',
          style: caption.copyWith(color: inkMuted),
        ),
      ],
    );
  }
}

/// 주변 5km 화장실·편의점·낚시점 카드.
/// 항목을 탭하면 네이버지도·카카오맵·티맵 연결 팝업이 뜬다.
class _NearbyCard extends StatelessWidget {
  final NearbyInfo info;
  final String stationName;

  const _NearbyCard({required this.info, required this.stationName});

  Widget _section(BuildContext context, Color color, String label,
      List<NearbyPlace> places) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 6),
            Text(label, style: bodySm.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 2),
        if (places.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 15, top: 2, bottom: 4),
            child: Text('5km 내 없음',
                style: caption.copyWith(color: inkTertiary)),
          )
        else
          for (final p in places.take(4))
            InkWell(
              onTap: () => showPlaceActions(
                context,
                place: p,
                color: color,
                typeLabel: label,
                fromName: stationName,
              ),
              borderRadius: BorderRadius.circular(radiusXs),
              child: Padding(
                padding:
                    const EdgeInsets.only(left: 15, top: 5, bottom: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(p.name,
                          style: bodySm, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      p.distanceM >= 1000
                          ? '${(p.distanceM / 1000).toStringAsFixed(1)}km'
                          : '${p.distanceM.round()}m',
                      style: bodySm.copyWith(
                        color: inkMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        size: 14, color: inkTertiary),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, nearbyToiletColor, '화장실', info.toilets),
        const SizedBox(height: 8),
        const Divider(color: hairlineSoft, height: 1),
        const SizedBox(height: 8),
        _section(context, nearbyStoreColor, '편의점', info.convenienceStores),
        const SizedBox(height: 8),
        const Divider(color: hairlineSoft, height: 1),
        const SizedBox(height: 8),
        _section(context, nearbyShopColor, '낚시점', info.fishingShops),
        const SizedBox(height: 4),
        Text('카카오 로컬 기준 · 반경 5km · 탭하면 지도앱으로 연결',
            style: caption.copyWith(color: inkTertiary, fontSize: 10)),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: inkTertiary, size: 44),
            const SizedBox(height: 12),
            Text(
              '데이터를 불러오지 못했어요\n$error',
              textAlign: TextAlign.center,
              style: bodySm.copyWith(color: inkMuted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ink,
                foregroundColor: onPrimary,
                textStyle: buttonText,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radiusMd)),
              ),
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
