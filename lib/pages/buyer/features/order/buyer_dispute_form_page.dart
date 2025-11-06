import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

class BuyerDisputeFormPage extends StatefulWidget {
  final String orderId;
  final String invoiceId;

  const BuyerDisputeFormPage({
    super.key,
    required this.orderId,
    required this.invoiceId,
  });

  @override
  State<BuyerDisputeFormPage> createState() => _BuyerDisputeFormPageState();
}

class _BuyerDisputeFormPageState extends State<BuyerDisputeFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  
  String? _selectedReason;
  final List<String> _reasons = [
    'Barang tidak sampai',
    'Barang rusak/cacat',
    'Barang tidak sesuai deskripsi',
    'Barang berbeda dengan yang dipesan',
    'Lainnya',
  ];

  final List<File> _evidenceImages = [];
  File? _evidenceVideo; // Video unboxing
  bool _submitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_evidenceImages.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maksimal 5 foto bukti')),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _evidenceImages.add(File(pickedFile.path));
      });
    }
  }

  Future<void> _removeImage(int index) async {
    setState(() {
      _evidenceImages.removeAt(index);
    });
  }

  Future<void> _pickVideo() async {
    if (_evidenceVideo != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video sudah dipilih. Hapus dulu untuk ganti.')),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2), // max 2 menit
    );

    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final fileSize = await file.length();
      
      // Max 50MB
      if (fileSize > 50 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video terlalu besar! Maksimal 50MB')),
        );
        return;
      }

      setState(() {
        _evidenceVideo = file;
      });
    }
  }

  Future<void> _removeVideo() async {
    setState(() {
      _evidenceVideo = null;
    });
  }

  Future<List<String>> _uploadEvidence() async {
    final List<String> urls = [];

    // Upload images
    for (int i = 0; i < _evidenceImages.length; i++) {
      try {
        final file = _evidenceImages[i];
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = 'disputes/${widget.orderId}/image_$timestamp\_$i.jpg';
        
        final ref = FirebaseStorage.instance.ref().child(path);
        await ref.putFile(file);
        final url = await ref.getDownloadURL();
        urls.add(url);
      } catch (e) {
        print('Upload image error: $e');
      }
    }

    // Upload video (WAJIB)
    if (_evidenceVideo != null) {
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = 'disputes/${widget.orderId}/video_$timestamp.mp4';
        
        final ref = FirebaseStorage.instance.ref().child(path);
        await ref.putFile(_evidenceVideo!);
        final url = await ref.getDownloadURL();
        urls.add(url);
      } catch (e) {
        print('Upload video error: $e');
        rethrow; // Video wajib, jadi throw error
      }
    }

    return urls;
  }

  Future<void> _submitDispute() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih alasan komplain')),
      );
      return;
    }

    // Validasi: Video wajib
    if (_evidenceVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video unboxing wajib dilampirkan sebagai bukti!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validasi: Minimal 1 foto
    if (_evidenceImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimal 1 foto bukti harus dilampirkan!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // Cek status order dulu
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .get();

      if (!orderDoc.exists) {
        throw Exception('Order tidak ditemukan');
      }

      final orderStatus = (orderDoc.data()?['status'] ?? '').toString().toUpperCase();
      
      // Debug log
      print('🔍 Order Status: $orderStatus');
      print('🔍 Order ID: ${widget.orderId}');
      
      if (orderStatus != 'SHIPPED') {
        throw Exception(
          'Status pesanan saat ini: $orderStatus\n'
          'Hanya pesanan dengan status SHIPPED yang bisa dilaporkan.\n\n'
          'Mohon tunggu hingga seller mengirim pesanan.'
        );
      }

      // Upload evidence images
      print('📤 Uploading evidence...');
      final evidenceUrls = await _uploadEvidence();
      print('✅ Evidence uploaded: ${evidenceUrls.length} files');

      // Call Cloud Function
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast2',
      );
      
      print('📞 Calling createDispute function...');
      final result = await functions.httpsCallable('createDispute').call({
        'orderId': widget.orderId,
        'reason': _selectedReason,
        'description': _descriptionController.text.trim(),
        'evidence': evidenceUrls,
      });
      
      print('✅ Dispute created: ${result.data}');

      if (!mounted) return;

      // Show success dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF28A745), size: 28),
              const SizedBox(width: 12),
              Text(
                'Laporan Terkirim',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'Laporan Anda telah diterima dan sedang diproses oleh tim admin. '
            'Kami akan mengirim notifikasi setelah ada keputusan.',
            style: GoogleFonts.dmSans(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Navigator.of(context).pop(); // close form
                Navigator.of(context).pop(); // back to order list
              },
              child: Text(
                'OK',
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1C55C0),
                ),
              ),
            ),
          ],
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      print('❌ Functions Error: ${e.code} - ${e.message}');
      print('❌ Details: ${e.details}');
      
      // Better error messages
      String errorMsg = e.message ?? 'Gagal mengirim laporan';
      if (e.code == 'failed-precondition') {
        errorMsg = 'Status pesanan tidak valid.\n${e.message}';
      } else if (e.code == 'unauthenticated') {
        errorMsg = 'Anda harus login terlebih dahulu';
      } else if (e.code == 'permission-denied') {
        errorMsg = 'Anda tidak memiliki akses ke pesanan ini';
      } else if (e.code == 'already-exists') {
        errorMsg = 'Laporan sudah pernah dibuat untuk pesanan ini';
      } else if (e.code == 'internal') {
        errorMsg = 'Error internal server.\nPastikan Cloud Functions sudah di-deploy.\n\nDetail: ${e.message}';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      print('❌ General Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi kesalahan: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF373E3C)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Laporkan Masalah',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF373E3C),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Order info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nomor Pesanan',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: const Color(0xFF777777),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '#${widget.invoiceId}',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF373E3C),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Reason dropdown
            Text(
              'Alasan Komplain *',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF373E3C),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedReason,
              decoration: InputDecoration(
                hintText: 'Pilih alasan',
                filled: true,
                fillColor: const Color(0xFFF8F8F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              items: _reasons.map((reason) {
                return DropdownMenuItem(
                  value: reason,
                  child: Text(
                    reason,
                    style: GoogleFonts.dmSans(fontSize: 14),
                  ),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedReason = value),
            ),

            const SizedBox(height: 20),

            // Description
            Text(
              'Detail Keluhan',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF373E3C),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Ceritakan masalah yang Anda alami...',
                hintStyle: GoogleFonts.dmSans(
                  color: const Color(0xFFBBBBBB),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: const Color(0xFFF8F8F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              style: GoogleFonts.dmSans(fontSize: 14),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Deskripsi wajib diisi';
                }
                if (val.trim().length < 20) {
                  return 'Minimal 20 karakter';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            // Evidence photos
            Text(
              'Bukti Foto',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF373E3C),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload maksimal 5 foto sebagai bukti (barang rusak, tidak sesuai, dll)',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: const Color(0xFF777777),
              ),
            ),
            const SizedBox(height: 12),

            // Image grid
            if (_evidenceImages.isNotEmpty)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _evidenceImages.asMap().entries.map((entry) {
                  final index = entry.key;
                  final file = entry.value;
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          file,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeImage(index),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),

            if (_evidenceImages.length < 5) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.add_photo_alternate),
                label: Text(
                  'Tambah Foto',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1C55C0),
                  side: const BorderSide(color: Color(0xFF1C55C0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Video Evidence (WAJIB)
            Text(
              'Video Unboxing (WAJIB) *',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFFF3449),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload video unboxing sebagai bukti utama komplain. Maksimal 50MB, durasi 2 menit.',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: const Color(0xFF777777),
              ),
            ),
            const SizedBox(height: 12),

            // Video preview or picker
            if (_evidenceVideo != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF28A745), width: 2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.video_library, color: Color(0xFF28A745), size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Video Terpilih',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF373E3C),
                            ),
                          ),
                          const SizedBox(height: 4),
                          FutureBuilder<int>(
                            future: _evidenceVideo!.length(),
                            builder: (context, snapshot) {
                              final size = snapshot.data ?? 0;
                              final sizeMB = (size / (1024 * 1024)).toStringAsFixed(2);
                              return Text(
                                '$sizeMB MB',
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: const Color(0xFF777777),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _removeVideo,
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.videocam),
                label: Text(
                  'Pilih Video Unboxing',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF3449),
                  side: const BorderSide(color: Color(0xFFFF3449), width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),

            const SizedBox(height: 32),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submitDispute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3449),
                  disabledBackgroundColor: const Color(0xFFCCCCCC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Kirim Laporan',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
