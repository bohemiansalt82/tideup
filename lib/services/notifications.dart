/// 만조·간조 로컬 알림.
///
/// 지점별 토글(prefs `notify_{id}`)이 켜져 있으면, 앞으로 예보된
/// 만조/간조 각각 1시간 전에 로컬 알림을 예약한다. 백그라운드 갱신은
/// 없으므로 앱을 열 때마다 다음 이틀치를 다시 예약하는 단순한 방식.
/// (웹은 미지원 — kIsWeb 가드)
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';

class TideNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static bool get supported => !kIsWeb;

  static Future<void> init() async {
    if (kIsWeb || _inited) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (_) {}
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    _inited = true;
  }

  static Future<bool> isEnabled(String stationId) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('notify_$stationId') ?? false;
  }

  /// 토글 — 켜면 권한 요청 후 예약, 끄면 예약 취소.
  /// 반환값: 최종 on/off 상태.
  static Future<bool> setEnabled(
      Station station, List<TideEvent> events, bool on) async {
    if (kIsWeb) return false;
    await init();
    final p = await SharedPreferences.getInstance();
    if (!on) {
      await p.setBool('notify_${station.id}', false);
      await _cancelFor(station.id);
      return false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    bool granted = true;
    if (android != null) {
      granted = await android.requestNotificationsPermission() ?? true;
    } else {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      granted = await ios?.requestPermissions(
              alert: true, badge: true, sound: true) ??
          true;
    }
    if (!granted) return false;
    await p.setBool('notify_${station.id}', true);
    await scheduleFor(station, events);
    return true;
  }

  static int _baseId(String stationId) => stationId.hashCode & 0x3FFFFF;

  static Future<void> _cancelFor(String stationId) async {
    final base = _baseId(stationId);
    for (var i = 0; i < 12; i++) {
      await _plugin.cancel(base + i);
    }
  }

  /// 앞으로의 만조/간조 1시간 전 알림 예약 (최대 12건).
  static Future<void> scheduleFor(
      Station station, List<TideEvent> events) async {
    if (kIsWeb) return;
    await init();
    await _cancelFor(station.id);
    final now = DateTime.now();
    final fmt = DateFormat('HH:mm');
    final base = _baseId(station.id);
    var i = 0;
    for (final e in events) {
      if (i >= 12) break;
      final fireAt = e.time.subtract(const Duration(hours: 1));
      if (fireAt.isBefore(now)) continue;
      await _plugin.zonedSchedule(
        base + i,
        '${e.isHigh ? '만조' : '간조'} 1시간 전 — ${station.name}',
        '${e.isHigh ? '만조' : '간조'} ${fmt.format(e.time)} · ${e.levelCm.round()}cm',
        tz.TZDateTime.from(fireAt, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'tide',
            '만조·간조 알림',
            channelDescription: '만조/간조 1시간 전 알림',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      i++;
    }
  }
}
