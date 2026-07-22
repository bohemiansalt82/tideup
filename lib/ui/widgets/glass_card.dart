import 'package:flutter/material.dart';

import '../theme.dart';

/// 크림 캔버스 위에 뜨는 흰색 타일 (DESIGN.md feature-card / product-mockup-card).
///
/// 그림자 없이 흰 배경 + 1px 헤어라인으로만 깊이를 만든다.
/// 차트 등 "목업" 성격의 카드는 [mockup]을 켜서 16px 라운드를 쓴다.
class GlassCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget child;
  final Widget? trailing; // 타이틀 행 우측 (예: 알림 토글)
  final EdgeInsetsGeometry padding;
  final bool mockup; // true → rounded.xl(16), false → rounded.lg(12)

  const GlassCard({
    super.key,
    this.title,
    this.icon,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(24),
    this.mockup = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surface1,
        borderRadius: BorderRadius.circular(mockup ? radiusXl : radiusLg),
        border: Border.all(color: hairline),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: inkMuted),
                const SizedBox(width: 6),
              ],
              Text(title!, style: eyebrow),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ]),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}
