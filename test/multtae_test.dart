import 'package:flutter_test/flutter_test.dart';

import 'package:bitewind/logic/multtae.dart';
import 'package:bitewind/logic/sun_moon.dart';

void main() {
  group('물때 계산', () {
    test('7물때식: 음력 1일 = 7물, 8일 = 조금, 9일 = 무시, 10일 = 1물', () {
      // 2026-02-17 = 음력 1월 1일 (설날)
      final seollal = multaeFor(DateTime(2026, 2, 17), MultaeSystem.west7);
      expect(seollal.lunarDay, 1);
      expect(seollal.label, '7물');

      final jogeum = multaeFor(DateTime(2026, 2, 24), MultaeSystem.west7);
      expect(jogeum.lunarDay, 8);
      expect(jogeum.label, '조금');

      final musi = multaeFor(DateTime(2026, 2, 25), MultaeSystem.west7);
      expect(musi.label, '무시');

      final onemul = multaeFor(DateTime(2026, 2, 26), MultaeSystem.west7);
      expect(onemul.lunarDay, 10);
      expect(onemul.label, '1물');
    });

    test('8물때식: 음력 1일 = 8물, 무시 없이 조금 다음 바로 1물', () {
      final seollal = multaeFor(DateTime(2026, 2, 17), MultaeSystem.south8);
      expect(seollal.label, '8물');

      final jogeum = multaeFor(DateTime(2026, 2, 24), MultaeSystem.south8);
      expect(jogeum.label, '조금');

      final onemul = multaeFor(DateTime(2026, 2, 25), MultaeSystem.south8);
      expect(onemul.label, '1물');
    });

    test('지역별 물때식: 서해=7물때식, 남해동부=8물때식', () {
      expect(systemForLocation(37.45, 126.59), MultaeSystem.west7); // 인천
      expect(systemForLocation(34.78, 126.38), MultaeSystem.west7); // 목포
      expect(systemForLocation(35.10, 129.04), MultaeSystem.south8); // 부산
      expect(systemForLocation(34.83, 128.43), MultaeSystem.south8); // 통영
    });
  });

  group('일출·일몰·월령', () {
    test('7월 인천 일출은 5~6시, 일몰은 19~20시대', () {
      final sun = sunTimesFor(DateTime(2026, 7, 18), 37.45, 126.59);
      expect(sun.sunrise, isNotNull);
      expect(sun.sunset, isNotNull);
      expect(sun.sunrise!.hour, inInclusiveRange(4, 6));
      expect(sun.sunset!.hour, inInclusiveRange(19, 20));
    });

    test('월령은 0~29.53 범위', () {
      final age = moonAge(DateTime(2026, 7, 18));
      expect(age, inInclusiveRange(0, 29.6));
    });

    test('보름 무렵 월령 (음력 15일 부근)', () {
      // 2026-08-28 = 음력 7월 16일 무렵 → 월령 14~16
      final age = moonAge(DateTime(2026, 8, 28));
      expect(age, inInclusiveRange(13, 17));
    });
  });
}
