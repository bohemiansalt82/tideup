import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../logic/multtae.dart';
import '../models/models.dart';
import '../services/geocoding_api.dart';
import '../services/repository.dart';
import 'station_page.dart';
import 'theme.dart';

/// 검색으로 추가할 수 있는 관측소 반경 한계 (km).
const _maxStationDistanceKm = 20.0;

/// 지오코딩 검색 결과 한 건 — 최근접 관측소 거리 포함.
class _RemoteHit {
  final Station station;
  final double distKm;
  final String region;

  const _RemoteHit(this.station, this.distKm, this.region);

  bool get addable => distKm <= _maxStationDistanceKm;
}

/// 홈 — 아이폰 날씨 앱의 도시 목록처럼 지점 요약 카드가 리스트로 쌓인다.
///
/// 상단 검색은 내장 목록(관측소·해변·선착장 등)을 즉시 거르고,
/// 없는 지명은 OpenStreetMap 지오코딩으로 찾아 최근접 관측소가
/// 20km 이내면 추가할 수 있다. 카드 탭 → 상세, 스와이프 삭제,
/// 길게 눌러 드래그 정렬.
class HomePage extends StatefulWidget {
  final Repository repository;

  const HomePage({super.key, required this.repository});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Station>? _favorites;
  Station? _myLocation; // GPS 기반 "내 위치" 지점 (관측소 20km 이내일 때만)
  String _query = '';
  final _searchController = TextEditingController();
  late final GeocodingApi _geocoder =
      GeocodingApi(kakaoRestApiKey: widget.repository.config.kakaoRestApiKey);
  Timer? _debounce;
  List<_RemoteHit> _remote = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await widget.repository.init();
    final favs = await widget.repository.loadFavorites();
    if (mounted) setState(() => _favorites = favs);
    _initLocation(); // 위치는 백그라운드로 — 실패해도 무시
  }

  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final (nearest, dist) =
          widget.repository.nearestStation(pos.latitude, pos.longitude);
      if (dist > 20) return; // 바다에서 너무 멀면 표시하지 않음
      if (mounted) {
        setState(() {
          _myLocation = Station(
            id: 'MYLOC',
            code: nearest.code,
            name: '내 위치',
            type: '현위치',
            lat: pos.latitude,
            lon: pos.longitude,
          );
        });
      }
    } catch (_) {
      // 위치 실패는 조용히 무시
    }
  }

  Future<void> _refresh() async {
    widget.repository.clearCache();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    final q = v.trim();
    setState(() {
      _query = q;
      _remote = const [];
    });
    _debounce?.cancel();
    if (q.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _remoteSearch(q);
    });
  }

  Future<void> _remoteSearch(String q) async {
    setState(() => _searching = true);
    List<GeoPlace> found = const [];
    try {
      found = await _geocoder.search(q);
    } catch (_) {
      // 네트워크 실패 — 내장 목록 결과만 표시
    }
    if (!mounted || q != _query) return; // 뒤늦게 도착한 응답 무시
    final hits = <_RemoteHit>[];
    for (final g in found) {
      final (nearest, dist) =
          widget.repository.nearestStation(g.lat, g.lon);
      hits.add(_RemoteHit(
        Station(
          id: 'G_${g.lat.toStringAsFixed(4)}_${g.lon.toStringAsFixed(4)}',
          code: nearest.code,
          name: g.name,
          type: g.type,
          lat: g.lat,
          lon: g.lon,
        ),
        dist,
        g.region,
      ));
    }
    setState(() {
      _remote = hits;
      _searching = false;
    });
  }

  /// 검색 결과 항목 탭 → 상세로 (리스트에 추가하지 않음).
  void _openDetail(Station s) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StationPage(repository: widget.repository, station: s),
      ),
    );
  }

  Future<void> _add(Station s) async {
    final favs = _favorites!;
    if (favs.any((f) => f.id == s.id)) return;
    setState(() {
      favs.add(s);
      _query = '';
      _remote = const [];
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
    await widget.repository.saveFavorites(favs);
  }

  @override
  Widget build(BuildContext context) {
    final favs = _favorites;
    final all = widget.repository.allLocations;
    final locals = _query.isEmpty || favs == null
        ? const <Station>[]
        : all
              .where(
                (s) =>
                    s.name.contains(_query) &&
                    !favs.any((f) => f.id == s.id),
              )
              .toList();

    return Scaffold(
      backgroundColor: canvas,
      // 키보드가 올라와도 Stack 하단 검색창을 viewInsets로 직접 올리므로 false
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Text('물때', style: displayMd),
                ),
                if (favs == null)
                  const Expanded(
                    child:
                        Center(child: CircularProgressIndicator(color: ink)),
                  )
                else if (_query.isNotEmpty)
                  Expanded(child: _buildSearchResults(locals))
                else
                  Expanded(child: _buildFavoriteList(favs)),
              ],
            ),
          ),
          _buildFloatingSearch(context),
        ],
      ),
    );
  }

  /// 하단 플로팅 검색창 — 키보드 높이에 맞춰 위로 올라온다.
  Widget _buildFloatingSearch(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: (insets > 0 ? insets + 10 : safeBottom + 14),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: surface1,
            borderRadius: BorderRadius.circular(radiusXl),
            border: Border.all(color: hairline),
            boxShadow: [
              BoxShadow(
                color: ink.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            onChanged: _onQueryChanged,
            style: body,
            cursorColor: ink,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '지역·해변·선착장 검색 (예: 해운대, 궁평항…)',
              hintStyle: body.copyWith(color: inkTertiary),
              prefixIcon: const Icon(Icons.search, color: inkSubtle),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, color: inkSubtle, size: 20),
                      onPressed: () {
                        setState(() {
                          _query = '';
                          _remote = const [];
                          _searchController.clear();
                        });
                        FocusScope.of(context).unfocus();
                      },
                    ),
              filled: false,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(List<Station> locals) {
    final rows = <Widget>[];

    for (final s in locals) {
      final refName = widget.repository.stationNameOf(s.code) ?? s.code;
      rows.add(ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Row(
          children: [
            Flexible(child: Text(s.name, style: body)),
            const SizedBox(width: 8),
            _TypeChip(type: s.type),
          ],
        ),
        subtitle: Text(
          s.isPlace ? '조석 기준: $refName 관측소' : s.code,
          style: caption.copyWith(color: inkSubtle),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_circle_outline, color: ink),
          tooltip: '리스트에 추가',
          onPressed: () => _add(s),
        ),
        onTap: () => _openDetail(s),
      ));
    }

    // 지오코딩(지도 검색) 결과 — 내장 목록과 이름이 겹치면 생략
    final remote = _remote
        .where((h) => !locals.any((s) => s.name == h.station.name))
        .toList();
    if (remote.isNotEmpty || _searching) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Text('지도 검색', style: eyebrow),
      ));
    }
    if (_searching) {
      rows.add(const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(color: inkSubtle, strokeWidth: 2),
          ),
        ),
      ));
    }
    for (final h in remote) {
      final s = h.station;
      final refName = widget.repository.stationNameOf(s.code) ?? s.code;
      final distText = h.distKm < 10
          ? h.distKm.toStringAsFixed(1)
          : h.distKm.round().toString();
      rows.add(ListTile(
        enabled: h.addable,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Row(
          children: [
            Flexible(
              child: Text(
                s.name,
                style: body.copyWith(color: h.addable ? ink : inkTertiary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _TypeChip(type: s.type),
          ],
        ),
        subtitle: Text(
          h.addable
              ? '${h.region.isEmpty ? '' : '${h.region} · '}조석 기준: $refName 관측소 · ${distText}km'
              : '${h.region.isEmpty ? '' : '${h.region} · '}가까운 관측소($refName)가 ${distText}km — 20km 밖이라 추가할 수 없어요',
          style: caption.copyWith(
              color: h.addable ? inkSubtle : inkTertiary),
        ),
        trailing: h.addable
            ? IconButton(
                icon: const Icon(Icons.add_circle_outline, color: ink),
                tooltip: '리스트에 추가',
                onPressed: () => _add(s),
              )
            : const Icon(Icons.block, color: inkTertiary, size: 18),
        onTap: h.addable ? () => _openDetail(s) : null,
      ));
    }

    if (rows.isEmpty) {
      return Center(
        child: Text(
          _query.length < 2 ? '두 글자 이상 입력해주세요' : '검색 결과 없음',
          style: bodySm.copyWith(color: inkTertiary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: rows,
    );
  }

  Widget _buildFavoriteList(List<Station> favs) {
    return RefreshIndicator(
      color: ink,
      backgroundColor: surface1,
      onRefresh: _refresh,
      child: ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: favs.length,
      buildDefaultDragHandles: false,
      header: _myLocation == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _StationSummaryCard(
                repository: widget.repository,
                station: _myLocation!,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StationPage(
                      repository: widget.repository,
                      station: _myLocation!,
                    ),
                  ),
                ),
              ),
            ),
      proxyDecorator: (child, _, _) => child,
      onReorderItem: (oldIndex, newIndex) async {
        setState(() {
          final item = favs.removeAt(oldIndex);
          favs.insert(newIndex, item);
        });
        await widget.repository.saveFavorites(favs);
      },
      itemBuilder: (context, i) {
        final s = favs[i];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(s.id),
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Dismissible(
              key: ValueKey('dismiss-${s.id}'),
              direction: favs.length > 1
                  ? DismissDirection.endToStart
                  : DismissDirection.none,
              background: Container(
                decoration: BoxDecoration(
                  color: semanticError,
                  borderRadius: BorderRadius.circular(radiusLg),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete, color: onPrimary),
              ),
              onDismissed: (_) async {
                setState(() => favs.removeAt(i));
                await widget.repository.saveFavorites(favs);
              },
              child: _StationSummaryCard(
                repository: widget.repository,
                station: s,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StationPage(
                      repository: widget.repository,
                      station: s,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      ),
    );
  }
}

/// 장소 유형 배지 (해수욕장·선착장·항구 등).
class _TypeChip extends StatelessWidget {
  final String type;

  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: surface2,
        borderRadius: BorderRadius.circular(radiusXs),
      ),
      child: Text(type, style: caption.copyWith(color: inkMuted, fontSize: 11)),
    );
  }
}

/// 지점 요약 카드 — 아이폰 날씨의 도시 행에 해당.
/// 왼쪽에 지점명·다음 만조/간조, 오른쪽에 오늘 물때를 크게.
class _StationSummaryCard extends StatelessWidget {
  final Repository repository;
  final Station station;
  final VoidCallback onTap;

  const _StationSummaryCard({
    required this.repository,
    required this.station,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final multae =
        multaeFor(now, systemForLocation(station.lat, station.lon));

    return Material(
      color: surface1,
      borderRadius: BorderRadius.circular(radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radiusLg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radiusLg),
            border: Border.all(color: hairline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: FutureBuilder<StationDayData>(
            future: repository.loadStationData(station),
            builder: (context, snap) {
              final data = snap.data;
              // 현재 시각대의 날씨
              HourlyWeather? cur;
              if (data != null) {
                final hourStart =
                    DateTime(now.year, now.month, now.day, now.hour);
                for (final h in data.hourly) {
                  if (!h.time.isBefore(hourStart)) {
                    cur = h;
                    break;
                  }
                }
              }
              final night = now.hour < 6 || now.hour >= 20;
              final (wxIcon, wxColor) =
                  weatherIcon(cur?.weatherCode, night: night);

              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                station.name,
                                style: cardTitle.copyWith(fontSize: 20),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (station.isPlace) ...[
                              const SizedBox(width: 6),
                              _TypeChip(type: station.type),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        _tideEventLines(now, data, snap),
                        const SizedBox(height: 2),
                        Text(
                          '음력 ${multae.lunarMonth}월 ${multae.lunarDay}일 · '
                          '${multae.system == MultaeSystem.west7 ? "7물때식" : "8물때식"}',
                          style: caption.copyWith(color: inkSubtle),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (cur != null) ...[
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(wxIcon, color: wxColor, size: 22),
                        if (cur.tempC != null)
                          Text('${cur.tempC!.round()}\u00b0',
                              style: caption.copyWith(color: inkMuted)),
                      ],
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(multae.label,
                      style: displayMd.copyWith(fontSize: 34, height: 1.0)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, color: inkTertiary, size: 20),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 오늘 만조/간조를 2개씩 끊어 줄바꿈. 지난 건 흐리게, 다음 건 진하게.
  Widget _tideEventLines(
      DateTime now, StationDayData? data, AsyncSnapshot snap) {
    if (data == null) {
      return Text(
        snap.hasError ? '\ubd88\ub7ec\uc624\uae30 \uc2e4\ud328' : '\ubd88\ub7ec\uc624\ub294 \uc911\u2026',
        style: bodySm.copyWith(color: inkTertiary),
      );
    }
    final today = DateTime(now.year, now.month, now.day);
    final events = data.tideEvents
        .where((e) =>
            e.time.year == today.year &&
            e.time.month == today.month &&
            e.time.day == today.day)
        .toList();
    if (events.isEmpty) {
      return Text('\uc608\ubcf4 \uc5c6\uc74c', style: bodySm.copyWith(color: inkTertiary));
    }
    final fmt = DateFormat('HH:mm');
    Widget chip(TideEvent e) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(e.isHigh ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12, color: e.isHigh ? reportBlue : reportOrange),
            const SizedBox(width: 1),
            Text(
              fmt.format(e.time),
              style: bodySm.copyWith(
                color: e.time.isAfter(now) ? ink : inkTertiary,
                fontWeight:
                    e.time.isAfter(now) ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < events.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                chip(events[i]),
                if (i + 1 < events.length) ...[
                  const SizedBox(width: 16),
                  chip(events[i + 1]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
