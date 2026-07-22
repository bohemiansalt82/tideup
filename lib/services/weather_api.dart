/// 날씨·파고 예보 클라이언트.
///
/// 1순위: 기상청 단기예보 (공공데이터포털 키 필요) — 기온·바람·강수.
/// 폴백: Open-Meteo (키 불필요) — 기온·바람·강수·파고까지 제공.
/// 기상청 단기예보에는 파고(WAV) 항목이 해안 격자에서만 오므로,
/// 파고는 Open-Meteo Marine으로 보충한다.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// 위경도 → 기상청 격자 (LCC DFS 변환).
({int x, int y}) kmaGrid(double lat, double lon) {
  const re = 6371.00877 / 5.0; // 지구 반경 / 격자 간격(5km)
  const slat1 = 30.0 * math.pi / 180.0;
  const slat2 = 60.0 * math.pi / 180.0;
  const olon = 126.0 * math.pi / 180.0;
  const olat = 38.0 * math.pi / 180.0;
  const xo = 43.0, yo = 136.0;

  final sn = math.log(math.cos(slat1) / math.cos(slat2)) /
      math.log(math.tan(math.pi * 0.25 + slat2 * 0.5) /
          math.tan(math.pi * 0.25 + slat1 * 0.5));
  final sf = math.pow(math.tan(math.pi * 0.25 + slat1 * 0.5), sn) *
      math.cos(slat1) /
      sn;
  final ro = re * sf / math.pow(math.tan(math.pi * 0.25 + olat * 0.5), sn);

  final ra = re *
      sf /
      math.pow(math.tan(math.pi * 0.25 + lat * math.pi / 180.0 * 0.5), sn);
  var theta = lon * math.pi / 180.0 - olon;
  if (theta > math.pi) theta -= 2.0 * math.pi;
  if (theta < -math.pi) theta += 2.0 * math.pi;
  theta *= sn;

  return (
    x: (ra * math.sin(theta) + xo + 0.5).floor(),
    y: (ro - ra * math.cos(theta) + yo + 0.5).floor(),
  );
}

abstract class WeatherApi {
  Future<List<HourlyWeather>> fetchHourly(double lat, double lon);
}

/// Open-Meteo — 키 없이 사용 가능한 폴백.
class OpenMeteoApi implements WeatherApi {
  final http.Client _client;
  OpenMeteoApi({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<List<HourlyWeather>> fetchHourly(double lat, double lon) async {
    final forecastUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'hourly':
          'temperature_2m,wind_speed_10m,wind_direction_10m,precipitation,weather_code',
      'wind_speed_unit': 'ms',
      'timezone': 'Asia/Seoul',
      'forecast_days': '2',
    });
    final marineUri = Uri.https('marine-api.open-meteo.com', '/v1/marine', {
      'latitude': '$lat',
      'longitude': '$lon',
      'hourly': 'wave_height,sea_surface_temperature',
      'timezone': 'Asia/Seoul',
      'forecast_days': '2',
    });

    final results = await Future.wait([
      _client.get(forecastUri).timeout(const Duration(seconds: 15)),
      _client
          .get(marineUri)
          .timeout(const Duration(seconds: 15))
          .then<http.Response?>((r) => r)
          .catchError((_) => null),
    ]);

    final fRes = results[0]!;
    if (fRes.statusCode != 200) return const [];
    final f = json.decode(fRes.body) as Map<String, dynamic>;
    final h = f['hourly'] as Map<String, dynamic>;
    final times = (h['time'] as List).cast<String>();

    Map<String, double?> waveByTime = {};
    Map<String, double?> sstByTime = {};
    final mRes = results[1];
    if (mRes != null && mRes.statusCode == 200) {
      final m = json.decode(mRes.body) as Map<String, dynamic>;
      final mh = m['hourly'] as Map<String, dynamic>?;
      if (mh != null) {
        final mTimes = (mh['time'] as List).cast<String>();
        final waves = (mh['wave_height'] as List? ?? const []);
        final ssts = (mh['sea_surface_temperature'] as List? ?? const []);
        for (var i = 0; i < mTimes.length; i++) {
          if (waves.length > i) {
            waveByTime[mTimes[i]] = (waves[i] as num?)?.toDouble();
          }
          if (ssts.length > i) {
            sstByTime[mTimes[i]] = (ssts[i] as num?)?.toDouble();
          }
        }
      }
    }

    List<num?> col(String key) =>
        ((h[key] as List?) ?? const []).cast<num?>();
    final temp = col('temperature_2m');
    final wind = col('wind_speed_10m');
    final windDir = col('wind_direction_10m');
    final precip = col('precipitation');
    final code = col('weather_code');

    final out = <HourlyWeather>[];
    for (var i = 0; i < times.length; i++) {
      out.add(HourlyWeather(
        time: DateTime.parse(times[i]),
        tempC: temp.length > i ? temp[i]?.toDouble() : null,
        windSpeedMs: wind.length > i ? wind[i]?.toDouble() : null,
        windDirDeg: windDir.length > i ? windDir[i]?.toDouble() : null,
        precipitationMm: precip.length > i ? precip[i]?.toDouble() : null,
        weatherCode: code.length > i ? code[i]?.toInt() : null,
        waveHeightM: waveByTime[times[i]],
        waterTempC: sstByTime[times[i]],
      ));
    }
    return out;
  }
}

/// 기상청 단기예보 (getVilageFcst).
class KmaApi implements WeatherApi {
  final String serviceKey;
  final http.Client _client;
  final OpenMeteoApi _marineFallback;

  KmaApi(this.serviceKey, {http.Client? client})
      : _client = client ?? http.Client(),
        _marineFallback = OpenMeteoApi(client: client);

  @override
  Future<List<HourlyWeather>> fetchHourly(double lat, double lon) async {
    final grid = kmaGrid(lat, lon);
    // 단기예보 발표 시각: 02,05,08,11,14,17,20,23시 (발표 후 10분 뒤 제공)
    var base = DateTime.now().subtract(const Duration(minutes: 30));
    final slots = [23, 20, 17, 14, 11, 8, 5, 2];
    int baseHour = slots.firstWhere((s) => base.hour >= s, orElse: () => 23);
    if (base.hour < 2) {
      base = base.subtract(const Duration(days: 1));
      baseHour = 23;
    }
    final baseDate =
        '${base.year}${base.month.toString().padLeft(2, '0')}${base.day.toString().padLeft(2, '0')}';

    final uri = Uri.https(
        'apis.data.go.kr', '/1360000/VilageFcstInfoService_2.0/getVilageFcst', {
      'serviceKey': serviceKey,
      'numOfRows': '600',
      'pageNo': '1',
      'dataType': 'JSON',
      'base_date': baseDate,
      'base_time': '${baseHour.toString().padLeft(2, '0')}00',
      'nx': '${grid.x}',
      'ny': '${grid.y}',
    });

    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200 || !res.body.trim().startsWith('{')) {
      // 키 문제/장애 시 Open-Meteo로 폴백
      return _marineFallback.fetchHourly(lat, lon);
    }
    final j = json.decode(res.body) as Map<String, dynamic>;
    final items = (((j['response'] as Map?)?['body'] as Map?)?['items']
        as Map?)?['item'] as List?;
    if (items == null) return _marineFallback.fetchHourly(lat, lon);

    // (날짜+시각) → 카테고리 값 모음
    final byTime = <String, Map<String, String>>{};
    for (final it in items.cast<Map<String, dynamic>>()) {
      final key = '${it['fcstDate']}${it['fcstTime']}';
      (byTime[key] ??= {})[it['category'] as String] =
          it['fcstValue'].toString();
    }

    // 파고·수온 보충용 Open-Meteo 데이터
    Map<DateTime, double?> waveMap = {};
    Map<DateTime, double?> sstMap = {};
    try {
      final om = await _marineFallback.fetchHourly(lat, lon);
      waveMap = {for (final h in om) h.time: h.waveHeightM};
      sstMap = {for (final h in om) h.time: h.waterTempC};
    } catch (_) {}

    final out = <HourlyWeather>[];
    final keys = byTime.keys.toList()..sort();
    for (final key in keys) {
      final v = byTime[key]!;
      final time = DateTime(
        int.parse(key.substring(0, 4)),
        int.parse(key.substring(4, 6)),
        int.parse(key.substring(6, 8)),
        int.parse(key.substring(8, 10)),
      );
      double? d(String cat) => double.tryParse(v[cat] ?? '');
      // PCP는 "강수없음" 또는 "1.0mm" 형태
      double? pcp;
      final pcpRaw = v['PCP'];
      if (pcpRaw != null) {
        pcp = double.tryParse(pcpRaw.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;
      }
      // SKY(하늘상태)+PTY(강수형태) → 대략적인 WMO 코드로 변환
      int? wmo;
      final sky = int.tryParse(v['SKY'] ?? '');
      final pty = int.tryParse(v['PTY'] ?? '');
      if (pty != null && pty > 0) {
        wmo = switch (pty) {
          1 => 61, // 비
          2 => 67, // 비/눈
          3 => 71, // 눈
          4 => 80, // 소나기
          _ => 61,
        };
      } else if (sky != null) {
        wmo = switch (sky) {
          1 => 0, // 맑음
          3 => 2, // 구름많음
          4 => 3, // 흐림
          _ => 1,
        };
      }
      out.add(HourlyWeather(
        time: time,
        tempC: d('TMP'),
        windSpeedMs: d('WSD'),
        windDirDeg: d('VEC'),
        precipitationMm: pcp,
        weatherCode: wmo,
        waveHeightM: d('WAV') ?? waveMap[time],
        waterTempC: sstMap[time],
      ));
    }
    return out;
  }
}
