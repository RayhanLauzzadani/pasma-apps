import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Custom Tab Bar dengan yellow underline seperti Persetujuan Toko
class AdminProductTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;

  const AdminProductTabBar({
    super.key,
    required this.selectedIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = ["Menunggu Persetujuan", "Terverifikasi"];
    final textStyle = GoogleFonts.dmSans(fontWeight: FontWeight.bold, fontSize: 15);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painters = List.generate(tabs.length, (i) {
          final tp = TextPainter(
            text: TextSpan(text: tabs[i], style: textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          return tp;
        });

        const spacing = 32.0;
        final lefts = <double>[];
        double left = 0;
        for (int i = 0; i < tabs.length; i++) {
          lefts.add(left);
          left += painters[i].width + spacing;
        }

        final underlineLeft = selectedIndex == 0 ? lefts[0] : lefts[1] - 4.0;
        final underlineWidth = painters[selectedIndex].width;

        return SizedBox(
          height: 40,
          child: Stack(
            alignment: Alignment.bottomLeft,
            children: [
              // Base line
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 2,
                  child: ColoredBox(color: Color(0x11B2B2B2)),
                ),
              ),
              // Tab labels
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(tabs.length, (i) {
                  final isActive = selectedIndex == i;
                  return GestureDetector(
                    onTap: isActive ? null : () => onTabChanged(i),
                    child: Container(
                      margin: EdgeInsets.only(right: i == 0 ? spacing : 0),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.ease,
                        style: GoogleFonts.dmSans(
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                          fontSize: 15,
                          color: isActive ? const Color(0xFF202020) : const Color(0xFFB2B2B2),
                        ),
                        child: Text(tabs[i]),
                      ),
                    ),
                  );
                }),
              ),
              // Yellow underline
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.ease,
                left: underlineLeft,
                bottom: 0,
                child: Container(
                  width: underlineWidth,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD600),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
