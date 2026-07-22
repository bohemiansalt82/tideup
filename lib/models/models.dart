/// BiteWind 공용 데이터 모델.
library;

/// 물때를 볼 수 있는 지점 — 조위관측소 자체이거나, 해수욕장·선착장·항구
/// 같은 장소. 장소는 조석 데이터를 가장 가까운 조위관측소([code])에서
/// 가져오고, 날씨·일출몰은 장소 좌표([lat]/[lon])로 계산한다.
class Station {
  final String id; // 고유 id — 관측소는 code와 동일, 장소는 P_* 형태
  final String code; // 조석 데이터를 가져올 조위관측소 코드 (예: DT_0001)
  final String name; // 예: 인천 / 해운대해수욕장 / 궁평항
  final String type; // '관측소' | '해수욕장' | '선착장' | '항구' | '방파제' 등
  final double lat;
  final double lon;

  const Station({
    required this.code,
    required this.name,
    required this.lat,
    required this.lon,
    String? id,
    this.type = '관측소',
  }) : id = id ?? code;

  bool get isPlace => type != '관측소';

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'type': type,
        'lat': lat,
        'lon': lon,
      };

  factory Station.fromJson(Map<String, dynamic> j) => Station(
        id: j['id'] as String?,
        code: j['code'] as String,
        name: j['name'] as String,
        type: j['type'] as String? ?? '관측소',
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );
}

/// 만조/간조 이벤트.
enum TideEventType { high, low }

class TideEvent {
  final DateTime time;
  final double levelCm; // 조위 (cm)
  final TideEventType type;

  const TideEvent({
    required this.time,
    required this.levelCm,
    required this.type,
  });

  bool get isHigh => type == TideEventType.high;

  Map<String, dynamic> toJson() => {
        't': time.toIso8601String(),
        'l': levelCm,
        'h': isHigh,
      };

  factory TideEvent.fromJson(Map<String, dynamic> j) => TideEvent(
        time: DateTime.parse(j['t'] as String),
        levelCm: (j['l'] as num).toDouble(),
        type: j['h'] == true ? TideEventType.high : TideEventType.low,
      );
}

/// 시계열 조위 한 점 (예측 곡선용).
class TidePoint {
  final DateTime time;
  final double levelCm;

  const TidePoint(this.time, this.levelCm);

  Map<String, dynamic> toJson() =>
      {'t': time.toIso8601String(), 'l': levelCm};

  factory TidePoint.fromJson(Map<String, dynamic> j) =>
      TidePoint(DateTime.parse(j['t'] as String), (j['l'] as num).toDouble());
}

/// 시간별 날씨 예보 한 칸.
class HourlyWeather {
  final DateTime time;
  final double? tempC; // 기온
  final double? windSpeedMs; // 풍속 m/s
  final double? windDirDeg; // 풍향 (도, 북=0)
  final double? waveHeightM; // 파고 m
  final double? waterTempC; // 수온 (해수면 온도)
  final int? weatherCode; // WMO weather code (Open-Meteo 기준)
  final double? precipitationMm;

  const HourlyWeather({
    required this.time,
    this.tempC,
    this.windSpeedMs,
    this.windDirDeg,
    this.waveHeightM,
    this.waterTempC,
    this.weatherCode,
    this.precipitationMm,
  });

  Map<String, dynamic> toJson() => {
        't': time.toIso8601String(),
        'te': tempC,
        'ws': windSpeedMs,
        'wd': windDirDeg,
        'wv': waveHeightM,
        'wt': waterTempC,
        'c': weatherCode,
        'p': precipitationMm,
      };

  factory HourlyWeather.fromJson(Map<String, dynamic> j) => HourlyWeather(
        time: DateTime.parse(j['t'] as String),
        tempC: (j['te'] as num?)?.toDouble(),
        windSpeedMs: (j['ws'] as num?)?.toDouble(),
        windDirDeg: (j['wd'] as num?)?.toDouble(),
        waveHeightM: (j['wv'] as num?)?.toDouble(),
        waterTempC: (j['wt'] as num?)?.toDouble(),
        weatherCode: (j['c'] as num?)?.toInt(),
        precipitationMm: (j['p'] as num?)?.toDouble(),
      );
}

/// 현재/요약 해양·기상 상태.
class MarineNow {
  final double? waterTempC; // 수온
  final double? airTempC;
  final double? windSpeedMs;
  final double? windDirDeg;
  final double? waveHeightM;

  const MarineNow({
    this.waterTempC,
    this.airTempC,
    this.windSpeedMs,
    this.windDirDeg,
    this.waveHeightM,
  });

  Map<String, dynamic> toJson() => {
        'wt': waterTempC,
        'at': airTempC,
        'ws': windSpeedMs,
        'wd': windDirDeg,
        'wv': waveHeightM,
      };

  factory MarineNow.fromJson(Map<String, dynamic> j) => MarineNow(
        waterTempC: (j['wt'] as num?)?.toDouble(),
        airTempC: (j['at'] as num?)?.toDouble(),
        windSpeedMs: (j['ws'] as num?)?.toDouble(),
        windDirDeg: (j['wd'] as num?)?.toDouble(),
        waveHeightM: (j['wv'] as num?)?.toDouble(),
      );
}

/// 어종별 낚시지수 (공식 바다낚시지수 예보).
class FishingSpeciesIndex {
  final String species; // 감성돔, 농어, 돌돔, 우럭, 참돔 …
  final String? morning; // 오전 등급 (매우좋음/좋음/보통/나쁨/매우나쁨)
  final String? afternoon; // 오후 등급

  const FishingSpeciesIndex({
    required this.species,
    this.morning,
    this.afternoon,
  });

  Map<String, dynamic> toJson() =>
      {'s': species, 'm': morning, 'a': afternoon};

  factory FishingSpeciesIndex.fromJson(Map<String, dynamic> j) =>
      FishingSpeciesIndex(
        species: j['s'] as String,
        morning: j['m'] as String?,
        afternoon: j['a'] as String?,
      );
}

/// 국립해양조사원 공식 바다낚시지수 예보 (포인트 단위).
class FishingForecast {
  final String pointName; // 예: 가거도
  final double distanceKm; // 지점과 낚시포인트 사이 거리
  final String? tidePhase; // 물때 (대조기/중조기/소조기)
  final List<FishingSpeciesIndex> species;

  const FishingForecast({
    required this.pointName,
    required this.distanceKm,
    this.tidePhase,
    required this.species,
  });

  Map<String, dynamic> toJson() => {
        'p': pointName,
        'd': distanceKm,
        't': tidePhase,
        's': species.map((e) => e.toJson()).toList(),
      };

  factory FishingForecast.fromJson(Map<String, dynamic> j) => FishingForecast(
        pointName: j['p'] as String,
        distanceKm: (j['d'] as num).toDouble(),
        tidePhase: j['t'] as String?,
        species: (j['s'] as List)
            .map((e) => FishingSpeciesIndex.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 주변 편의시설 한 곳 (카카오 로컬 검색 결과).
class NearbyPlace {
  final String name;
  final String address;
  final double distanceM; // 지점에서의 거리 (m)
  final double lat;
  final double lon;

  const NearbyPlace({
    required this.name,
    required this.address,
    required this.distanceM,
    required this.lat,
    required this.lon,
  });
}

/// 지점 주변 1km 편의 정보.
class NearbyInfo {
  final List<NearbyPlace> toilets; // 화장실
  final List<NearbyPlace> fishingShops; // 낚시점·낚시용품
  final List<NearbyPlace> convenienceStores; // 편의점

  const NearbyInfo({
    required this.toilets,
    required this.fishingShops,
    this.convenienceStores = const [],
  });

  bool get isEmpty =>
      toilets.isEmpty && fishingShops.isEmpty && convenienceStores.isEmpty;
}

/// 한 지점의 하루치 종합 데이터 묶음.
class StationDayData {
  final Station station;
  final List<TideEvent> tideEvents; // 오늘~내일 만조/간조
  final List<TidePoint> tideCurve; // 오늘 예측 조위 곡선
  final List<HourlyWeather> hourly; // 시간별 날씨
  final MarineNow now;
  final FishingForecast? fishing; // 공식 바다낚시지수 (없으면 휴리스틱 사용)
  final bool isMock; // 목업 데이터 여부 (조석 기준)
  final DateTime? fetchedAt; // 데이터를 받아온 시각 (오프라인 캐시 표기용)

  const StationDayData({
    required this.station,
    required this.tideEvents,
    required this.tideCurve,
    required this.hourly,
    required this.now,
    this.fishing,
    this.isMock = false,
    this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
        'events': tideEvents.map((e) => e.toJson()).toList(),
        'curve': tideCurve.map((e) => e.toJson()).toList(),
        'hourly': hourly.map((e) => e.toJson()).toList(),
        'now': now.toJson(),
        'fishing': fishing?.toJson(),
        'mock': isMock,
        'at': fetchedAt?.toIso8601String(),
      };

  factory StationDayData.fromJson(Station station, Map<String, dynamic> j) =>
      StationDayData(
        station: station,
        tideEvents: (j['events'] as List)
            .map((e) => TideEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        tideCurve: (j['curve'] as List)
            .map((e) => TidePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        hourly: (j['hourly'] as List)
            .map((e) => HourlyWeather.fromJson(e as Map<String, dynamic>))
            .toList(),
        now: MarineNow.fromJson(j['now'] as Map<String, dynamic>),
        fishing: j['fishing'] == null
            ? null
            : FishingForecast.fromJson(j['fishing'] as Map<String, dynamic>),
        isMock: j['mock'] == true,
        fetchedAt:
            j['at'] == null ? null : DateTime.parse(j['at'] as String),
      );
}
