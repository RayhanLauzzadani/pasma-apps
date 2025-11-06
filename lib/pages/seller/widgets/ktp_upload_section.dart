import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:pasma_apps/pages/seller/widgets/ktp_instruction_page.dart';

// Tambahkan
import 'package:provider/provider.dart';
import 'package:pasma_apps/pages/seller/providers/seller_registration_provider.dart';

class KtpUploadSection extends StatefulWidget {
  final VoidCallback? onShowInstruction;
  final Function(String? nik, String? nama)? onKtpOcrResult;

  const KtpUploadSection({
    super.key,
    this.onShowInstruction,
    this.onKtpOcrResult,
  });

  @override
  State<KtpUploadSection> createState() => _KtpUploadSectionState();
}

class _KtpUploadSectionState extends State<KtpUploadSection> {
  bool _loading = false;

  Future<void> _pickDocument(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
      );

      if (result == null) return;

      final pickedFile = File(result.files.single.path!);
      final fileExtension = result.files.single.extension?.toLowerCase();
      final fileSize = result.files.single.size;

      // Validasi ukuran file (maksimal 5MB)
      if (fileSize > 5 * 1024 * 1024) {
        if (mounted) {
          Flushbar(
            message: "Ukuran file terlalu besar. Maksimal 5MB.",
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red.shade600,
            icon: const Icon(Icons.error_outline, color: Colors.white, size: 28),
            margin: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(12),
            flushbarPosition: FlushbarPosition.TOP,
          ).show(context);
        }
        return;
      }

      // Validasi format file
      if (fileExtension != 'pdf' && fileExtension != 'doc' && fileExtension != 'docx') {
        if (mounted) {
          Flushbar(
            message: "Format file tidak didukung. Gunakan PDF, DOC, atau DOCX.",
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red.shade600,
            icon: const Icon(Icons.error_outline, color: Colors.white, size: 28),
            margin: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(12),
            flushbarPosition: FlushbarPosition.TOP,
          ).show(context);
        }
        return;
      }

      // Simpan ke provider
      Provider.of<SellerRegistrationProvider>(context, listen: false)
          .setKtpFile(pickedFile);

      if (mounted) {
        Flushbar(
          message: "Dokumen KTP berhasil dipilih!",
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green.shade600,
          icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 28),
          margin: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(12),
          flushbarPosition: FlushbarPosition.TOP,
        ).show(context);
      }
    } catch (e) {
      if (mounted) {
        Flushbar(
          message: "Gagal memilih file: $e",
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red.shade600,
          icon: const Icon(Icons.error_outline, color: Colors.white, size: 28),
          margin: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(12),
          flushbarPosition: FlushbarPosition.TOP,
        ).show(context);
      }
    }
  }

  void _deleteImage(BuildContext context) {
    // Clear di Provider
    Provider.of<SellerRegistrationProvider>(context, listen: false)
        .setKtpFile(null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ktpFile =
        Provider.of<SellerRegistrationProvider>(context).ktpFile;

    // Dapatkan nama file dan ekstensi
    String? fileName;
    String? fileExtension;
    if (ktpFile != null) {
      fileName = ktpFile.path.split('/').last;
      fileExtension = fileName.split('.').last.toUpperCase();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CARD abu-abu
        Container(
          width: double.infinity,
          color: const Color(0xFFF2F2F3),
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "Dokumen Transkrip/FRS",
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                        color: const Color(0xFF373E3C),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '*',
                      style: TextStyle(
                        color: Color(0xFFFF4D4D),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: ktpFile == null
                    ? GestureDetector(
                        onTap: _loading ? null : () => _pickDocument(context),
                        child: DottedBorder(
                          borderType: BorderType.RRect,
                          radius: const Radius.circular(10),
                          color: const Color(0xFFD1D5DB),
                          dashPattern: const [6, 3],
                          strokeWidth: 1.4,
                          child: Container(
                            width: double.infinity,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SvgPicture.asset(
                                        'assets/icons/registration/plus.svg',
                                        width: 40,
                                        height: 40,
                                        color: const Color(0xFFBDBDBD),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        "Upload Dokumen Transkrip/FRS",
                                        style: GoogleFonts.dmSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFF6B7280),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "PDF, DOC, DOCX (Max 5MB)",
                                        style: GoogleFonts.dmSans(
                                          fontSize: 12,
                                          color: const Color(0xFF9CA3AF),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF10B981),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  fileExtension ?? '',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName ?? '',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF111827),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: Color(0xFF10B981),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "File berhasil dipilih",
                                        style: GoogleFonts.dmSans(
                                          fontSize: 12,
                                          color: const Color(0xFF10B981),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _deleteImage(context),
                              icon: const Icon(
                                Icons.close,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Tombol Instruksi di bawah, center
        Center(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const KtpInstructionPage(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2056D3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Lihat Instruksi",
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Upload dokumen Transkrip Nilai atau FRS (Formulir Rencana Studi) dalam format PDF, DOC, atau DOCX. Pastikan dokumen asli dan terbaca dengan jelas. Maksimal ukuran file 5MB.",
            style: GoogleFonts.dmSans(
              color: const Color(0xFF373E3C),
              fontWeight: FontWeight.w400,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
