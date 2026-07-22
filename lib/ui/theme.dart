/// BiteWind 디자인 토큰 — DESIGN.md (Intercom 스타일) 기반.
///
/// 크림 캔버스(#F5F1EC) 위에 흰색 카드가 헤어라인 보더로 뜨는 구조.
/// 시스템 프라이머리는 차콜(#111111), 단일 액센트는 Fin 오렌지(#FF5600)로
/// 낚시 지수(이 앱의 "Fin"에 해당)에만 사용한다. 리포트 팔레트는
/// 조위 차트 등 분석 표면 안에서만 쓴다. 그림자 금지 — 깊이는
/// 크림→흰색 표면 전환과 헤어라인으로만 표현한다.
library;

import 'package:flutter/material.dart';

// ── Colors ──────────────────────────────────────────────
const ink = Color(0xFF111111);
const onPrimary = Color(0xFFFFFFFF);
const inkMuted = Color(0xFF626260);
const inkSubtle = Color(0xFF7B7B78);
const inkTertiary = Color(0xFF9C9FA5);
const canvas = Color(0xFFF5F1EC);
const surface1 = Color(0xFFFFFFFF);
const surface2 = Color(0xFFEBE7E1);
const inverseCanvas = Color(0xFF000000);
const hairline = Color(0xFFD3CEC6);
const hairlineSoft = Color(0xFFEBE7E1);
const finOrange = Color(0xFFFF5600);
const reportOrange = Color(0xFFFE4C02);
const reportBlue = Color(0xFF65B5FF);
const reportGreen = Color(0xFF0BDF50);
const semanticError = Color(0xFFC41C1C);

// ── Radii ───────────────────────────────────────────────
const radiusXs = 4.0;
const radiusMd = 8.0; // 버튼, 인풋
const radiusLg = 12.0; // 일반 카드
const radiusXl = 16.0; // 목업(차트) 카드

// ── Typography (Saans → Pretendard 대체) ─────────────────
const fontFamily = 'Pretendard';

const displayXl = TextStyle(
  fontFamily: fontFamily,
  fontSize: 72,
  fontWeight: FontWeight.w500,
  height: 1.05,
  letterSpacing: -2.0,
  color: ink,
);

const displayMd = TextStyle(
  fontFamily: fontFamily,
  fontSize: 40,
  fontWeight: FontWeight.w500,
  height: 1.15,
  letterSpacing: -0.8,
  color: ink,
);

const headline = TextStyle(
  fontFamily: fontFamily,
  fontSize: 28,
  fontWeight: FontWeight.w500,
  height: 1.20,
  letterSpacing: -0.5,
  color: ink,
);

const cardTitle = TextStyle(
  fontFamily: fontFamily,
  fontSize: 22,
  fontWeight: FontWeight.w500,
  height: 1.25,
  letterSpacing: -0.3,
  color: ink,
);

const bodyLg = TextStyle(
  fontFamily: fontFamily,
  fontSize: 18,
  fontWeight: FontWeight.w400,
  height: 1.5,
  letterSpacing: -0.1,
  color: ink,
);

const body = TextStyle(
  fontFamily: fontFamily,
  fontSize: 16,
  fontWeight: FontWeight.w400,
  height: 1.5,
  color: ink,
);

const bodySm = TextStyle(
  fontFamily: fontFamily,
  fontSize: 14,
  fontWeight: FontWeight.w400,
  height: 1.5,
  color: ink,
);

const caption = TextStyle(
  fontFamily: fontFamily,
  fontSize: 12,
  fontWeight: FontWeight.w400,
  height: 1.4,
  color: inkMuted,
);

const buttonText = TextStyle(
  fontFamily: fontFamily,
  fontSize: 15,
  fontWeight: FontWeight.w500,
  height: 1.2,
);

/// 섹션/카드 아이브로우 — 문장식 표기(all-caps 금지), 14px w500.
const eyebrow = TextStyle(
  fontFamily: fontFamily,
  fontSize: 14,
  fontWeight: FontWeight.w500,
  height: 1.3,
  color: inkMuted,
);

// ── 차트 "좋음"(골든타임) 하이라이트 배경 ──────────────
// 낚시 골든타임 느낌의 따뜻한 골드/앰버. 녹색보다 부드럽게 얹힌다.
const goodHighlight = Color(0xFFF3B23C);

// ── 주변 편의시설 블릿 색 ──────────────────────────────
const nearbyToiletColor = Color(0xFF4A9FE0); // 화장실 — 파란색
const nearbyStoreColor = Color(0xFF9C5FD1); // 편의점 — 보라색
const nearbyShopColor = Color(0xFF2FAE5B); // 낚시점 — 녹색

// ── Helpers ─────────────────────────────────────────────

/// WMO weather code → 이모지.
String weatherEmoji(int? code, {bool night = false}) {
  if (code == null) return night ? '🌙' : '☀️';
  if (code == 0) return night ? '🌙' : '☀️';
  if (code <= 2) return night ? '☁️' : '🌤️';
  if (code == 3) return '☁️';
  if (code <= 49) return '🌫️';
  if (code <= 59) return '🌦️';
  if (code <= 69) return '🌧️';
  if (code <= 79) return '🌨️';
  if (code <= 84) return '🌦️';
  if (code <= 94) return '🌨️';
  return '⛈️';
}

/// WMO weather code → (Material 아이콘, 색). 캔버스/위젯 공용.
(IconData, Color) weatherIcon(int? code, {bool night = false}) {
  const sun = Color(0xFFF6A609);
  const moon = Color(0xFF6C79C7);
  const cloud = Color(0xFF9AA3AD);
  const rain = Color(0xFF4A9FE0);
  const snow = Color(0xFF7EC8F0);
  const thunder = Color(0xFFF08C1A);
  if (code == null || code == 0) {
    return night ? (Icons.nightlight_round, moon) : (Icons.wb_sunny, sun);
  }
  if (code <= 2) {
    return night ? (Icons.nights_stay, moon) : (Icons.wb_cloudy, cloud);
  }
  if (code == 3) return (Icons.cloud, cloud);
  if (code <= 49) return (Icons.blur_on, cloud);
  if (code <= 69) return (Icons.water_drop, rain);
  if (code <= 79) return (Icons.ac_unit, snow);
  if (code <= 84) return (Icons.water_drop, rain);
  if (code <= 94) return (Icons.ac_unit, snow);
  return (Icons.flash_on, thunder);
}

/// 풍향(도) → 방위 문자열.
String windDirText(double? deg) {
  if (deg == null) return '-';
  const dirs = ['북', '북동', '동', '남동', '남', '남서', '서', '북서'];
  return dirs[(((deg + 22.5) % 360) / 45).floor()];
}
