import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pasma_apps/pages/seller/widgets/registration_app_bar.dart';

class KtpInstructionPage extends StatelessWidget {
  const KtpInstructionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(79),
        child: RegistrationAppBar(
          title: 'Instruksi',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 0),
        children: [
          const SizedBox(height: 16),
          // Dua gambar bersebelahan: transkrip.png dan frs.png
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/icons/registration/transkrip.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/icons/registration/frs.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Judul instruksi
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              "Upload Dokumen Identitas",
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF373E3C),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // List instruksi
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InstructionPoint(
                  number: "1.",
                  text: "Upload dokumen dalam format PDF, DOC, atau DOCX.",
                ),
                _InstructionPoint(
                  number: "2.",
                  text: "Pastikan dokumen asli, tidak hasil editan atau fotokopi.",
                ),
                _InstructionPoint(
                  number: "3.",
                  text: "Dokumen harus jelas dan mudah dibaca.",
                ),
                _InstructionPoint(
                  number: "4.",
                  text: "Ukuran file maksimal 5MB.",
                ),
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  color: const Color(0xFFE4E8EE),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Widget point instruksi
class _InstructionPoint extends StatelessWidget {
  final String number;
  final String text;
  const _InstructionPoint({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF9A9A9A),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF9A9A9A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
