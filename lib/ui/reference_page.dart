import 'package:flutter/material.dart';

import 'theme.dart';

/// 낚시 단위 변환표 — 메뉴에서 열리는 참고 화면.
/// 각 표는 카드로 분리되고, 열이 많은 표는 가로로 스크롤한다.
class ReferencePage extends StatelessWidget {
  const ReferencePage({super.key});

  // 무게: 오즈(oz) → 그람(g), 1 oz = 28.3495 g. 봉돌·루어 무게.
  static const List<(String, String)> _weight = [
    ('1/32', '0.9'),
    ('1/16', '1.8'),
    ('1/8', '3.5'),
    ('3/16', '5.3'),
    ('1/4', '7.1'),
    ('5/16', '8.9'),
    ('3/8', '10.6'),
    ('1/2', '14.2'),
    ('5/8', '17.7'),
    ('3/4', '21.3'),
    ('7/8', '24.8'),
    ('1', '28.3'),
    ('1½', '42.5'),
    ('2', '56.7'),
    ('3', '85.0'),
  ];

  // 길이: 인치(inch) → cm, 1 inch = 2.54 cm.
  static const List<(String, String)> _inch = [
    ('1"', '2.5'),
    ('2"', '5.1'),
    ('3"', '7.6'),
    ('4"', '10.2'),
    ('5"', '12.7'),
    ('6"', '15.2'),
    ('7"', '17.8'),
    ('8"', '20.3'),
    ('9"', '22.9'),
    ('10"', '25.4'),
    ('11"', '27.9'),
    ('12"', '30.5'),
  ];

  // 길이: 피트(ft) → cm, 1 ft = 30.48 cm. 낚싯대·리더 길이.
  static const List<(String, String)> _feet = [
    ("1'", '30.5'),
    ("2'", '61.0'),
    ("3'", '91.4'),
    ("4'", '121.9'),
    ("5'", '152.4'),
    ("6'", '182.9'),
    ("7'", '213.4'),
    ("8'", '243.8'),
    ("9'", '274.3'),
    ("10'", '304.8'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: ink, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text('낚시 단위표', style: displayMd.copyWith(fontSize: 20)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _ConvCard(
                    title: '무게 · 오즈 → 그람',
                    subtitle: '봉돌·루어 무게 (1 oz = 28.35 g)',
                    tables: [
                      _TableSpec(leftUnit: 'oz', rightUnit: 'g', cells: _weight),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ConvCard(
                    title: '길이 · 인치·피트 → cm',
                    subtitle: '루어·낚싯대 길이 (1" = 2.54 cm, 1\' = 30.48 cm)',
                    tables: [
                      _TableSpec(
                          leftUnit: 'inch', rightUnit: 'cm', cells: _inch),
                      _TableSpec(
                          leftUnit: 'feet', rightUnit: 'cm', cells: _feet),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableSpec {
  final String leftUnit;
  final String rightUnit;
  final List<(String, String)> cells;
  const _TableSpec(
      {required this.leftUnit, required this.rightUnit, required this.cells});
}

class _ConvCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_TableSpec> tables;

  const _ConvCard({
    required this.title,
    required this.subtitle,
    required this.tables,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surface1,
        borderRadius: BorderRadius.circular(radiusXl),
        border: Border.all(color: hairline),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: cardTitle.copyWith(fontSize: 17)),
          const SizedBox(height: 2),
          Text(subtitle, style: caption.copyWith(color: inkSubtle)),
          const SizedBox(height: 14),
          for (var i = 0; i < tables.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _HScrollTable(spec: tables[i]),
          ],
        ],
      ),
    );
  }
}

class _HScrollTable extends StatelessWidget {
  final _TableSpec spec;
  const _HScrollTable({required this.spec});

  static const _cellW = 62.0;
  static const _labelW = 52.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radiusMd),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: hairline),
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        child: Row(
          children: [
            // 좌측 고정 단위 열
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _fixedCell(spec.leftUnit, top: true),
                const _HLine(),
                _fixedCell(spec.rightUnit, top: false),
              ],
            ),
            const _VLine(),
            // 값들 — 가로 스크롤
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < spec.cells.length; i++)
                          _valueCell(spec.cells[i].$1,
                              top: true, first: i == 0),
                      ],
                    ),
                    const _HLine(),
                    Row(
                      children: [
                        for (var i = 0; i < spec.cells.length; i++)
                          _valueCell(spec.cells[i].$2,
                              top: false, first: i == 0),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fixedCell(String text, {required bool top}) {
    return Container(
      width: _labelW,
      height: 40,
      alignment: Alignment.center,
      color: surface2,
      child: Text(
        text,
        style: caption.copyWith(
          color: inkSubtle,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _valueCell(String text, {required bool top, required bool first}) {
    return Container(
      width: _cellW,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: top ? surface1 : surface1,
        border: Border(
          left: first
              ? BorderSide.none
              : const BorderSide(color: hairlineSoft),
        ),
      ),
      child: Text(
        text,
        style: top
            ? body.copyWith(fontWeight: FontWeight.w600)
            : bodySm.copyWith(
                color: finOrange, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _HLine extends StatelessWidget {
  const _HLine();
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: hairline);
}

class _VLine extends StatelessWidget {
  const _VLine();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 81, color: hairline);
}
