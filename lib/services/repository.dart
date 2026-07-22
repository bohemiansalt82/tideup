/// 데이터 저장소 — 실제 API와 목업을 하나의 인터페이스로 묶는다.
///
/// - KHOA 키가 있으면: KHOA(조석·수온·바람) + 기상청/Open-Meteo(예보)
/// - 키가 없으면: 전부 목업
/// - 즐겨찾기 지점은 shared_preferences에 저장
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/default_stations.dart';
import '../data/places.dart';
import '../logic/geo.dart';
import '../models/models.dart';
import 'app_config.dart';
import 'fishing_api.dart';
import 'khoa_api.dart';
import 'mock_data.dart';
import 'nearby_api.dart';
import 'tidebed_api.dart';
import 'weather_api.dart';

class Repository {
  final AppConfig config;
  final KhoaApi? _khoa;
  final TideBedApi? _tidebed;
  final WeatherApi _weather;
  final FishingApi? _fishing;
  final NearbyApi? _nearby;
  final MockDataSource _mock = MockDataSource();
  final Map<String, NearbyInfo> _nearbyCache = {};
  final Map<String, List<TideEvent>> _weekCache = {};

  List<Station> _allStations = defaultStations;
  List<Station> _allPlaces = const [];
  final Map<String, StationDayData> _cache = {};

  Repository(this.config)
      : _khoa = config.hasKhoaKey ? KhoaApi(config.khoaServiceKey) : null,
        // 바다누리 키가 없고 data.go.kr 키가 있으면 TideBED로 조석 실데이터
        _tidebed = (!config.hasKhoaKey && config.hasDataGoKrKey)
            ? TideBedApi(config.dataGoKrServiceKey)
            : null,
        _weather = config.hasKmaKey
            ? KmaApi(config.kmaServiceKey)
            : OpenMeteoApi(),
        _fishing = config.hasDataGoKrKey
            ? FishingApi(config.dataGoKrServiceKey)
            : null,
        _nearby =
            config.hasKakaoKey ? NearbyApi(config.kakaoRestApiKey) : null;

  bool get isLive => _khoa != null || _tidebed != null;

  /// 조위관측소 목록.
  List<Station> get allStations => _allStations;

  /// 검색 대상 전체 — 관측소 + 해수욕장·선착장·항구 등 장소.
  List<Station> get allLocations => [..._allStations, ..._allPlaces];

  /// [code]에 해당하는 조위관측소 이름 (없으면 null).
  String? stationNameOf(String code) {
    for (final s in _allStations) {
      if (s.code == code) return s.name;
    }
    return null;
  }

  /// 지점 주변 1km 편의시설 (카카오 키 없으면 null).
  Future<NearbyInfo?> loadNearby(Station station) async {
    if (_nearby == null) return null;
    final cached = _nearbyCache[station.id];
    if (cached != null) return cached;
    try {
      final info = await _nearby.fetch(station.lat, station.lon);
      _nearbyCache[station.id] = info;
      return info;
    } catch (_) {
      return null;
    }
  }

  /// 좌표에서 가장 가까운 조위관측소와 거리(km).
  (Station, double) nearestStation(double lat, double lon) {
    var nearest = _allStations.first;
    var best = double.infinity;
    for (final s in _allStations) {
      final d = haversineKm(lat, lon, s.lat, s.lon);
      if (d < best) {
        best = d;
        nearest = s;
      }
    }
    return (nearest, best);
  }

  /// 앱 시작 시 관측소 목록 갱신 (키 있을 때만).
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    // 캐시된 라이브 관측소 목록
    final cached = prefs.getString('stations');
    if (cached != null) {
      try {
        final list = (json.decode(cached) as List)
            .map((e) => Station.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) _allStations = list;
      } catch (_) {}
    }
    if (_khoa != null) {
      try {
        final live = await _khoa.fetchStations();
        if (live.isNotEmpty) {
          _allStations = live;
          await prefs.setString(
              'stations', json.encode(live.map((s) => s.toJson()).toList()));
        }
      } catch (_) {
        // 네트워크/키 문제 — 기본 목록으로 계속
      }
    }
    // 장소 목록 → 최근접 조위관측소 매핑
    _allPlaces = resolvePlaces(_allStations);
  }

  /// 즐겨찾기 지점 로드 (기본: 인천, 부산, 제주).
  ///
  /// v2는 Station 전체를 JSON으로 저장한다 — 지오코딩으로 추가한
  /// 커스텀 지역은 앱 내장 목록에 없어서 id만으로는 복원할 수 없기 때문.
  /// 구버전(v1, id 목록)은 최초 1회 마이그레이션된다.
  Future<List<Station>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final rawV2 = prefs.getString('favorites_v2');
    if (rawV2 != null) {
      try {
        final favs = (json.decode(rawV2) as List)
            .map((e) => Station.fromJson(e as Map<String, dynamic>))
            .toList();
        if (favs.isNotEmpty) return favs;
      } catch (_) {}
    }
    // v1 마이그레이션 (id 목록)
    final rawV1 = prefs.getStringList('favorites');
    if (rawV1 != null && rawV1.isNotEmpty) {
      final favs = <Station>[];
      for (final id in rawV1) {
        final match = allLocations.where((s) => s.id == id);
        if (match.isNotEmpty) favs.add(match.first);
      }
      if (favs.isNotEmpty) {
        await saveFavorites(favs);
        return favs;
      }
    }
    final defaults = ['인천', '부산', '제주'];
    return defaults
        .map((name) => _allStations.firstWhere(
              (s) => s.name.contains(name),
              orElse: () => _allStations.first,
            ))
        .toSet()
        .toList();
  }

  Future<void> saveFavorites(List<Station> stations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('favorites_v2',
        json.encode(stations.map((s) => s.toJson()).toList()));
  }

  /// 메모리 캐시 비우기 (당겨서 새로고침).
  void clearCache() {
    _cache.clear();
    _nearbyCache.clear();
    _weekCache.clear();
  }

  /// 한 지점의 종합 데이터.
  ///
  /// 네트워크 실패 시 마지막으로 저장한 오프라인 캐시를 반환한다
  /// (fetchedAt으로 기준 시각을 표시).
  Future<StationDayData> loadStationData(Station station,
      {bool refresh = false}) async {
    final key = '${station.id}-${DateTime.now().day}';
    if (!refresh && _cache.containsKey(key)) return _cache[key]!;

    StationDayData data;
    try {
      if (_khoa != null) {
        data = await _loadLive(station);
      } else if (_tidebed != null) {
        data = await _loadTideBed(station);
      } else {
        data = _mock.generate(station, DateTime.now());
      }

      // 공식 바다낚시지수 (키가 있으면 조석 목업 여부와 무관하게 실데이터)
      if (_fishing != null) {
        try {
          final fishing = await _fishing.fetchNearest(
              station.lat, station.lon, DateTime.now());
          if (fishing != null) {
            data = StationDayData(
              station: data.station,
              tideEvents: data.tideEvents,
              tideCurve: data.tideCurve,
              hourly: data.hourly,
              now: data.now,
              fishing: fishing,
              isMock: data.isMock,
              fetchedAt: data.fetchedAt,
            );
          }
        } catch (_) {
          // 낚시지수 실패는 치명적이지 않다 — 휴리스틱으로 폴백
        }
      }
    } catch (e) {
      // 1) 오프라인 캐시
      final cached = await _loadOfflineCache(station);
      if (cached != null) {
        _cache[key] = cached;
        return cached;
      }
      // 2) TideBED 미지원 지역(동해안 등) → 샘플로 폴백 (에러 화면 대신)
      if (_tidebed != null || _khoa != null) {
        final mock = _mock.generate(station, DateTime.now());
        _cache[key] = mock;
        return mock;
      }
      rethrow;
    }

    _cache[key] = data;
    await _saveOfflineCache(station, data);
    return data;
  }

  Future<void> _saveOfflineCache(Station station, StationDayData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'daycache_${station.id}', json.encode(data.toJson()));
    } catch (_) {}
  }

  Future<StationDayData?> _loadOfflineCache(Station station) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('daycache_${station.id}');
      if (raw == null) return null;
      return StationDayData.fromJson(
          station, json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// station.code에 해당하는 조위관측소 좌표 (TideBED 폴백용).
  (double, double) _refStationCoord(Station station) {
    for (final s in _allStations) {
      if (s.code == station.code) return (s.lat, s.lon);
    }
    return (station.lat, station.lon);
  }

  /// TideBED(조위 곡선) + Open-Meteo(날씨·수온·바람)로 하루 종합 데이터.
  Future<StationDayData> _loadTideBed(Station station) async {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    final (refLat, refLon) = _refStationCoord(station);

    final results = await Future.wait([
      _tidebed!.fetchDay(station.lat, station.lon, today,
          fallbackLat: refLat, fallbackLon: refLon),
      _tidebed.fetchDay(station.lat, station.lon, tomorrow,
          fallbackLat: refLat, fallbackLon: refLon),
      _weather.fetchHourly(station.lat, station.lon).catchError(
            (_) => <HourlyWeather>[],
          ),
    ]);
    final todayData = results[0] as TideBedDay;
    final tomorrowData = results[1] as TideBedDay;
    final hourly = results[2] as List<HourlyWeather>;

    final now = DateTime.now();
    HourlyWeather? nowHour;
    for (final h in hourly) {
      if (h.time.isAfter(now.subtract(const Duration(hours: 1)))) {
        nowHour = h;
        break;
      }
    }

    return StationDayData(
      station: station,
      tideEvents: [...todayData.events, ...tomorrowData.events],
      tideCurve: todayData.curve,
      hourly: hourly,
      fetchedAt: DateTime.now(),
      now: MarineNow(
        waterTempC: nowHour?.waterTempC,
        airTempC: nowHour?.tempC,
        windSpeedMs: nowHour?.windSpeedMs,
        windDirDeg: nowHour?.windDirDeg,
        waveHeightM: nowHour?.waveHeightM,
      ),
    );
  }

  /// 주간(오늘부터 7일) 만조/간조 목록 — 날짜별로 반환.
  Future<List<(DateTime, List<TideEvent>)>> loadWeek(Station station) async {
    final today = DateTime.now();
    final out = <(DateTime, List<TideEvent>)>[];
    for (var d = 0; d < 7; d++) {
      final date = DateTime(today.year, today.month, today.day + d);
      final key = '${station.id}-w-${date.month}-${date.day}';
      var events = _weekCache[key];
      if (events == null) {
        try {
          if (_khoa != null) {
            events = await _khoa.fetchHighLow(station.code, date);
          } else if (_tidebed != null) {
            final (refLat, refLon) = _refStationCoord(station);
            events = (await _tidebed.fetchDay(station.lat, station.lon, date,
                    fallbackLat: refLat, fallbackLon: refLon))
                .events;
          } else {
            events = _mock.eventsFor(station, date);
          }
        } catch (_) {
          // TideBED 미지원 지역 등 → 샘플로 폴백
          events = _mock.eventsFor(station, date);
        }
        _weekCache[key] = events;
      }
      out.add((
        date,
        events
            .where((e) =>
                e.time.year == date.year &&
                e.time.month == date.month &&
                e.time.day == date.day)
            .toList()
      ));
    }
    return out;
  }

  Future<StationDayData> _loadLive(Station station) async {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));

    // 병렬 요청
    final results = await Future.wait([
      _khoa!.fetchHighLow(station.code, today),
      _khoa.fetchHighLow(station.code, tomorrow),
      _khoa.fetchTideCurve(station.code, today),
      _khoa.fetchWaterTemp(station.code),
      _khoa.fetchWind(station.code),
      _weather.fetchHourly(station.lat, station.lon).catchError(
            (_) => <HourlyWeather>[],
          ),
    ]);

    final events = [
      ...results[0] as List<TideEvent>,
      ...results[1] as List<TideEvent>,
    ];
    final curve = results[2] as List<TidePoint>;
    final waterTemp = results[3] as double?;
    final (windSpeed, windDir) = results[4] as (double?, double?);
    final hourly = results[5] as List<HourlyWeather>;

    final now = DateTime.now();
    HourlyWeather? nowHour;
    for (final h in hourly) {
      if (h.time.isAfter(now.subtract(const Duration(hours: 1)))) {
        nowHour = h;
        break;
      }
    }

    return StationDayData(
      station: station,
      tideEvents: events,
      tideCurve: curve,
      fetchedAt: DateTime.now(),
      // 전체(오늘~내일)를 전달 — 조위 차트 레인은 하루 전체가 필요하다.
      hourly: hourly,
      now: MarineNow(
        waterTempC: waterTemp,
        airTempC: nowHour?.tempC,
        windSpeedMs: windSpeed ?? nowHour?.windSpeedMs,
        windDirDeg: windDir ?? nowHour?.windDirDeg,
        waveHeightM: nowHour?.waveHeightM,
      ),
    );
  }
}
