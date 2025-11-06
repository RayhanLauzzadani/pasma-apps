import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

class AdminDisputeDetailPage extends StatefulWidget {
  final String disputeId;

  const AdminDisputeDetailPage({
    super.key,
    required this.disputeId,
  });

  @override
  State<AdminDisputeDetailPage> createState() => _AdminDisputeDetailPageState();
}

class _AdminDisputeDetailPageState extends State<AdminDisputeDetailPage> {
  final _notesController = TextEditingController();
  bool _processing = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _resolveDispute(String resolution) async {
    // Validate admin notes for reject
    if (resolution == 'reject' && _notesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alasan penolakan wajib diisi')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          resolution == 'refund' ? 'Setujui Komplain?' : 'Tolak Komplain?',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.bold),
        ),
        content: Text(
          resolution == 'refund'
              ? 'Dana akan dikembalikan ke buyer dan seller tidak mendapat pembayaran.'
              : 'Komplain akan ditolak dan dana akan dicairkan ke seller.',
          style: GoogleFonts.dmSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: resolution == 'refund'
                  ? const Color(0xFF28A745)
                  : const Color(0xFFFF3449),
            ),
            child: Text(
              resolution == 'refund' ? 'Setujui' : 'Tolak',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processing = true);

    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast2',
      );

      await functions.httpsCallable('resolveDispute').call({
        'disputeId': widget.disputeId,
        'resolution': resolution,
        'adminNotes': _notesController.text.trim(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resolution == 'refund'
                ? 'Dispute disetujui, dana dikembalikan'
                : 'Dispute ditolak, dana dicairkan',
          ),
        ),
      );

      Navigator.pop(context); // kembali ke list
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Gagal memproses')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF373E3C)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Detail Komplain',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF373E3C),
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orderDisputes')
            .doc(widget.disputeId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Komplain tidak ditemukan'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final status = data['status'] as String? ?? 'open';
          final isResolved = status == 'resolved' || status == 'rejected';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status badge
                _buildStatusBadge(status),
                const SizedBox(height: 20),

                // Order info
                _buildInfoCard(
                  title: 'Informasi Pesanan',
                  children: [
                    _buildInfoRow('Invoice ID', data['invoiceId'] ?? 'N/A'),
                    _buildInfoRow('Order ID', data['orderId'] ?? 'N/A'),
                    _buildInfoRow(
                      'Tanggal Laporan',
                      _formatDate(data['createdAt'] as Timestamp?),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Order detail (untuk validasi)
                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('orders')
                      .doc(data['orderId'])
                      .get(),
                  builder: (context, orderSnapshot) {
                    if (!orderSnapshot.hasData || !orderSnapshot.data!.exists) {
                      return const SizedBox.shrink();
                    }

                    final orderData = orderSnapshot.data!.data() as Map<String, dynamic>;
                    final items = orderData['items'] as List<dynamic>? ?? [];
                    final amounts = orderData['amounts'] as Map<String, dynamic>? ?? {};
                    final total = amounts['total'] ?? 0;
                    final shippingAddress = orderData['shippingAddress'] as Map<String, dynamic>? ?? {};
                    final orderStatus = orderData['status'] ?? 'N/A';
                    final paymentStatus = orderData['payment']?['status'] ?? 'N/A';

                    return Column(
                      children: [
                        _buildInfoCard(
                          title: 'Detail Transaksi Order',
                          children: [
                            _buildInfoRow('Status Order', orderStatus),
                            _buildInfoRow('Status Pembayaran', paymentStatus),
                            _buildInfoRow(
                              'Total Pembayaran',
                              NumberFormat.currency(
                                locale: 'id_ID',
                                symbol: 'Rp ',
                                decimalDigits: 0,
                              ).format(total),
                            ),
                            _buildInfoRow(
                              'Alamat Pengiriman',
                              shippingAddress['address'] ?? shippingAddress['addressText'] ?? 'N/A',
                            ),
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              'Produk yang Dipesan:',
                              style: GoogleFonts.dmSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF373E3C),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...items.map((item) {
                              final name = item['name'] ?? 'Produk';
                              final qty = item['qty'] ?? 0;
                              final price = item['price'] ?? 0;
                              final variant = item['variant'] ?? '';
                              
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Product image
                                    if (item['imageUrl'] != null)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          item['imageUrl'],
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            width: 50,
                                            height: 50,
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.image, size: 24),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: GoogleFonts.dmSans(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF373E3C),
                                            ),
                                          ),
                                          if (variant.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              variant,
                                              style: GoogleFonts.dmSans(
                                                fontSize: 12,
                                                color: const Color(0xFF999999),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Text(
                                            '$qty x ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(price)}',
                                            style: GoogleFonts.dmSans(
                                              fontSize: 13,
                                              color: const Color(0xFF666666),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),

                // Dispute info
                _buildInfoCard(
                  title: 'Detail Komplain',
                  children: [
                    _buildInfoRow('Alasan', data['reason'] ?? '-'),
                    const SizedBox(height: 12),
                    Text(
                      'Deskripsi:',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF373E3C),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data['description'] ?? 'Tidak ada deskripsi',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: const Color(0xFF666666),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Evidence - pisahkan foto dan video
                if (data['evidence'] != null &&
                    (data['evidence'] as List).isNotEmpty) ...[
                  // Pisahkan foto dan video
                  Builder(
                    builder: (context) {
                      final evidenceList = data['evidence'] as List;
                      final images = <String>[];
                      final videos = <String>[];

                      for (final url in evidenceList) {
                        final urlStr = url.toString().toLowerCase();
                        if (urlStr.contains('.mp4') || 
                            urlStr.contains('.mov') || 
                            urlStr.contains('.avi') ||
                            urlStr.contains('.webm')) {
                          videos.add(url as String);
                        } else {
                          images.add(url as String);
                        }
                      }

                      return Column(
                        children: [
                          // Foto
                          if (images.isNotEmpty) ...[
                            _buildInfoCard(
                              title: '📸 Bukti Foto dari Pembeli',
                              children: [
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: images
                                      .map((url) => _buildEvidenceImage(url))
                                      .toList(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          
                          // Video
                          if (videos.isNotEmpty) ...[
                            _buildInfoCard(
                              title: '🎥 Video Unboxing dari Pembeli',
                              children: videos.map((url) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF5F5F5),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFF1C55C0)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.play_circle_filled, 
                                            color: Color(0xFF1C55C0), size: 48),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Video Evidence',
                                                  style: GoogleFonts.dmSans(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Tap untuk memutar video',
                                                  style: GoogleFonts.dmSans(
                                                    fontSize: 12,
                                                    color: const Color(0xFF777777),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () {
                                              // Open video in browser/external player
                                              // Untuk sementara show URL
                                              showDialog(
                                                context: context,
                                                builder: (_) => AlertDialog(
                                                  title: Text(
                                                    'Video URL',
                                                    style: GoogleFonts.dmSans(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  content: SelectableText(url),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context),
                                                      child: const Text('Tutup'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.open_in_new),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                      );
                    },
                  ),
                ],

                // Delivery Proof dari Seller (fetch dari order)
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('orders')
                      .doc(data['orderId'] as String?)
                      .snapshots(),
                  builder: (context, orderSnap) {
                    if (!orderSnap.hasData || !orderSnap.data!.exists) {
                      return const SizedBox.shrink();
                    }

                    final orderData = orderSnap.data!.data() as Map<String, dynamic>?;
                    final deliveryProof = orderData?['deliveryProof'] as Map<String, dynamic>?;

                    if (deliveryProof == null) {
                      return const SizedBox.shrink();
                    }

                    final method = deliveryProof['method'] as String?;
                    final trackingNumber = deliveryProof['trackingNumber'] as String?;
                    final proofImages = deliveryProof['proofImages'] as List?;

                    return Column(
                      children: [
                        _buildInfoCard(
                          title: '🚚 Bukti Pengiriman dari Penjual',
                          children: [
                            // Metode pengiriman
                            Row(
                              children: [
                                const Icon(Icons.local_shipping, 
                                  color: Color(0xFF1C55C0), size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Metode: ',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    color: const Color(0xFF777777),
                                  ),
                                ),
                                Text(
                                  method == 'courier' 
                                      ? 'Pakai Kurir' 
                                      : 'Kirim Sendiri',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF373E3C),
                                  ),
                                ),
                              ],
                            ),
                            
                            // Nomor resi (jika ada)
                            if (trackingNumber != null && trackingNumber.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.qr_code, 
                                    color: Color(0xFF1C55C0), size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Resi: ',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 13,
                                      color: const Color(0xFF777777),
                                    ),
                                  ),
                                  Expanded(
                                    child: SelectableText(
                                      trackingNumber,
                                      style: GoogleFonts.dmSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF373E3C),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            // Foto dokumentasi
                            if (proofImages != null && proofImages.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Dokumentasi Pengiriman:',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF373E3C),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: proofImages
                                    .map((url) => _buildEvidenceImage(url as String))
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),

                // Admin notes (if resolved)
                if (isResolved && data['adminNotes'] != null) ...[
                  _buildInfoCard(
                    title: 'Catatan Admin',
                    children: [
                      Text(
                        data['adminNotes'] as String,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: const Color(0xFF666666),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Resolved: ${_formatDate(data['resolvedAt'] as Timestamp?)}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: const Color(0xFF999999),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Admin action section (if not resolved yet)
                if (!isResolved) ...[
                  Text(
                    'Catatan Admin (Opsional)',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF373E3C),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Tambahkan catatan untuk buyer/seller...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: GoogleFonts.dmSans(fontSize: 14),
                  ),
                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _processing
                              ? null
                              : () => _resolveDispute('reject'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF3449),
                            disabledBackgroundColor: const Color(0xFFCCCCCC),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Tolak Komplain',
                            style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _processing
                              ? null
                              : () => _resolveDispute('refund'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF28A745),
                            disabledBackgroundColor: const Color(0xFFCCCCCC),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _processing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Refund Buyer',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor, textColor;
    String label;

    switch (status.toLowerCase()) {
      case 'open':
        bgColor = const Color(0xFFFFF3CD);
        textColor = const Color(0xFFFF9800);
        label = 'Terbuka';
        break;
      case 'investigating':
        bgColor = const Color(0xFFE3F2FD);
        textColor = const Color(0xFF2196F3);
        label = 'Diproses';
        break;
      case 'resolved':
        bgColor = const Color(0xFFD4EDDA);
        textColor = const Color(0xFF28A745);
        label = 'Selesai (Refund)';
        break;
      case 'rejected':
        bgColor = const Color(0xFFF8D7DA);
        textColor = const Color(0xFFFF3449);
        label = 'Ditolak';
        break;
      default:
        bgColor = const Color(0xFFEEEEEE);
        textColor = const Color(0xFF999999);
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF373E3C),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: const Color(0xFF999999),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF373E3C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceImage(String url) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 100,
            height: 100,
            color: Colors.grey[300],
            child: const Icon(Icons.broken_image),
          ),
        ),
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    final date = timestamp.toDate();
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }
}
