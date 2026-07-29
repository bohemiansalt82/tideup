/// 전체 지도용 격자 기상장 — Open-Meteo에서 한국 연안 격자의 시간별
/// 바람(풍속·풍향)과 수온(해수면 온도)을 한 번에 받아온다.
///
/// 여러 지점을 콤마로 넘기면 Open-Meteo가 배열로 응답한다.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class WindTempSample {
  final double? windSpeedMs;
  final double? windDirDeg;
  final double? waterTempC;

  const WindTempSample({this.windSpeedMs, this.windDirDeg, this.waterTempC});
}

class FieldPoint {
  final double lat;
  final double lon;
  final List<WindTempSample> hours; // times와 같은 길이

  const FieldPoint({required this.lat, required this.lon, required this.hours});
}

class MapField {
  final List<FieldPoint> points;
  final List<DateTime> times;

  const MapField({required this.points, required this.times});

  bool get isEmpty => points.isEmpty || times.isEmpty;
}

class MapFieldApi {
  final http.Client _client;
  MapFieldApi({http.Client? client}) : _client = client ?? http.Client();

  /// 한국 연안을 덮는 격자 좌표.
  static List<(double, double)> _grid() {
    final pts = <(double, double)>[];
    for (var lat = 33.2; lat <= 38.8; lat += 0.6) {
      for (var lon = 124.6; lon <= 130.4; lon += 0.6) {
        pts.add((
          double.parse(lat.toStringAsFixed(2)),
          double.parse(lon.toStringAsFixed(2)),
        ));
      }
    }
    return pts;
  }

  Future<MapField> fetch() async {
    final grid = _grid();
    final lats = grid.map((p) => p.$1).join(',');
    final lons = grid.map((p) => p.$2).join(',');

    final forecastUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lats,
      'longitude': lons,
      'hourly': 'wind_speed_10m,wind_direction_10m',
      'wind_speed_unit': 'ms',
      'timezone': 'Asia/Seoul',
      'forecast_days': '2',
    });
    final marineUri = Uri.https('marine-api.open-meteo.com', '/v1/marine', {
      'latitude': lats,
      'longitude': lons,
      'hourly': 'sea_surface_temperature',
      'timezone': 'Asia/Seoul',
      'forecast_days': '2',
    });

    final results = await Future.wait([
      _client.get(forecastUri).timeout(const Duration(seconds: 20)),
      _client
          .get(marineUri)
          .timeout(const Duration(seconds: 20))
          .then<http.Response?>((r) => r)
          .catchError((_) => null),
    ]);

    final fRes = results[0]!;
    if (fRes.statusCode != 200) return const MapField(points: [], times: []);
    final fList = _asList(json.decode(fRes.body));

    // 해양(수온) — 실패해도 바람만으로 진행
    List<dynamic> mList = const [];
    final mRes = results[1];
    if (mRes != null && mRes.statusCode == 200) {
      mList = _asList(json.decode(mRes.body));
    }

    // 공통 시간축 (첫 지점 기준)
    final times = <DateTime>[];
    if (fList.isNotEmpty) {
      final t = ((fList.first['hourly'] as Map?)?['time'] as List?) ?? const [];
      for (final s in t.cast<String>()) {
        final dt = DateTime.tryParse(s);
        if (dt != null) times.add(dt);
      }
    }

    final points = <FieldPoint>[];
    for (var i = 0; i < grid.length && i < fList.length; i++) {
      final f = fList[i] as Map<String, dynamic>;
      final fh = f['hourly'] as Map<String, dynamic>?;
      final speed = ((fh?['wind_speed_10m'] as List?) ?? const []).cast<num?>();
      final dir =
          ((fh?['wind_direction_10m'] as List?) ?? const []).cast<num?>();

      List<num?> sst = const [];
      if (i < mList.length) {
        final m = mList[i] as Map<String, dynamic>;
        sst = (((m['hourly'] as Map?)?['sea_surface_temperature'] as List?) ??
                const [])
            .cast<num?>();
      }

      final hours = <WindTempSample>[];
      for (var h = 0; h < times.length; h++) {
        hours.add(WindTempSample(
          windSpeedMs: speed.length > h ? speed[h]?.toDouble() : null,
          windDirDeg: dir.length > h ? dir[h]?.toDouble() : null,
          waterTempC: sst.length > h ? sst[h]?.toDouble() : null,
        ));
      }
      points.add(FieldPoint(lat: grid[i].$1, lon: grid[i].$2, hours: hours));
    }

    return MapField(points: points, times: times);
  }

  static List<dynamic> _asList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) return [decoded];
    return const [];
  }
}

/// 격자 지점들에서 임의 좌표의 바람을 역거리가중(IDW)으로 보간.
/// 반환: (풍속 m/s, 풍향 도) — 데이터 없으면 null.
(double, double)? interpolateWind(
    List<FieldPoint> points, int hour, double lat, double lon) {
  double wu = 0, wv = 0, wsum = 0; // 벡터 성분으로 가중 평균
  for (final p in points) {
    if (hour >= p.hours.length) continue;
    final s = p.hours[hour];
    final spd = s.windSpeedMs, d = s.windDirDeg;
    if (spd == null || d == null) continue;
    final dLat = lat - p.lat, dLon = (lon - p.lon) * 0.8;
    final dist2 = dLat * dLat + dLon * dLon;
    // 먼 격자는 빨리 감쇠(제곱) — 지역별 흐름 차이가 살아난다.
    final w = 1.0 / (dist2 * dist2 + 0.0008);
    // 풍향(불어오는 방향)을 벡터로: u=동, v=북 (가는 방향 기준)
    final ang = (d + 180) * math.pi / 180;
    wu += w * spd * math.sin(ang);
    wv += w * spd * math.cos(ang);
    wsum += w;
  }
  if (wsum == 0) return null;
  final u = wu / wsum, v = wv / wsum;
  final speed = math.sqrt(u * u + v * v);
  var dirTo = math.atan2(u, v) * 180 / math.pi; // 가는 방향
  final dirFrom = (dirTo + 180) % 360;
  return (speed, dirFrom < 0 ? dirFrom + 360 : dirFrom);
}
