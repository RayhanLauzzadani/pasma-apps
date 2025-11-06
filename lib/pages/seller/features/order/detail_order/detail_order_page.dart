import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

// ➜ pastikan import ini ada
import 'package:pasma_apps/pages/seller/features/transaction/transaction_detail_page.dart';

enum OrderStatus { selesai, dibatalkan, dikirim, menunggu }

class DetailOrderPage extends StatefulWidget {
  final String orderId;
  const DetailOrderPage({super.key, required this.orderId});

  @override
  State<DetailOrderPage> createState() => _DetailOrderPageState();
}

class _DetailOrderPageState extends State<DetailOrderPage> {
  bool _showFullAddress = false;
  final List<File> _deliveryProofImages = [];
  bool _uploading = false;

  Future<void> _pickProofImage() async {
    if (_deliveryProofImages.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maksimal 3 foto dokumentasi')),
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
        _deliveryProofImages.add(File(pickedFile.path));
      });
    }
  }

  Future<void> _removeProofImage(int index) async {
    setState(() {
      _deliveryProofImages.removeAt(index);
    });
  }

  Future<void> _uploadAndConfirmDelivery() async {
    if (_deliveryProofImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimal 1 foto dokumentasi wajib diupload!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _uploading = true);

    try {
      // Upload semua foto
      final List<String> uploadedUrls = [];
      for (int i = 0; i < _deliveryProofImages.length; i++) {
        final file = _deliveryProofImages[i];
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = 'delivery_proofs/${widget.orderId}/self_delivered_$timestamp\_$i.jpg';
        final ref = FirebaseStorage.instance.ref().child(path);
        
        await ref.putFile(file);
        final url = await ref.getDownloadURL();
        uploadedUrls.add(url);
      }

      // Update deliveryProof di order
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
        'deliveryProof.proofImages': uploadedUrls,
        'deliveryProof.uploadedAt': FieldValue.serverTimestamp(),
        'deliveryProof.confirmed': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      setState(() {
        _uploading = false;
        _deliveryProofImages.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Bukti pengiriman berhasil diupload!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal upload: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderStream =
        FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: orderStream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.hasData || !snap.data!.exists) {
              return Center(
                  child: Text('Pesanan tidak ditemukan', style: GoogleFonts.dmSans()));
            }

            final data = snap.data!.data()!;
            final orderDocId = snap.data!.id; // ID asli dokumen
            final invoiceId = (data['invoiceId'] as String?)?.trim();
            final displayedId =
                (invoiceId != null && invoiceId.isNotEmpty) ? invoiceId : orderDocId;

            final statusStr =
                ((data['status'] ?? data['shippingAddress']?['status'] ?? 'PLACED') as String)
                    .toUpperCase();
            final orderStatus = _statusFrom(statusStr);

            final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

            // buyer info
            final buyerId = (data['buyerId'] ?? '') as String;

            // alamat kirim
            final ship = (data['shippingAddress'] as Map<String, dynamic>?) ?? {};
            final addressLabel = (ship['label'] ?? '-') as String;
            final addressText = (ship['address'] ?? '-') as String;
            final shippingAddress = '$addressLabel, $addressText';

            // items
            final items = List<Map<String, dynamic>>.from(data['items'] ?? []);

            // amounts (dukung typo lama 'mounts')
            final amounts =
                (data['amounts'] ?? data['mounts'] ?? <String, dynamic>{}) as Map<String, dynamic>;
            final subtotal = ((amounts['subtotal'] as num?) ?? 0).toInt();
            final shippingFee = ((amounts['shipping'] as num?) ?? 0).toInt();
            // final taxFee = ((amounts['tax'] as num?) ?? 0).toInt(); // seller tidak tampilkan
            final sellerTotal = subtotal + shippingFee;

            // payment
            final method = ((data['payment']?['method'] ?? 'abc_payment') as String).toUpperCase();
            final methodText = method == 'ABC_PAYMENT' ? 'PASMA Payment' : method;

            final addressThreshold = 60;
            final isLongAddress = shippingAddress.length > addressThreshold;

            // nota tetap bisa dilihat meskipun dibatalkan
            final showNota = true;

            // stream nama buyer
            final userStream = buyerId.isEmpty
                ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
                : FirebaseFirestore.instance.collection('users').doc(buyerId).snapshots();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: userStream,
              builder: (context, userSnap) {
                final buyerName = (userSnap.data?.data()?['name'] ?? 'Pembeli') as String;

                return CustomScrollView(
                  slivers: [
                    // Sticky Header
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _StickyHeaderDelegate(
                        minHeight: 66,
                        maxHeight: 66,
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 6),
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2056D3),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                              const SizedBox(width: 15),
                              Text('Detail Pesanan',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF232323))),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Header: nama pembeli + status + invoice/order id yang ditampilkan
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Username Pembeli',
                                      style: GoogleFonts.dmSans(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17,
                                          color: const Color(0xFF232323))),
                                  const SizedBox(height: 2),
                                  Text(buyerName,
                                      style: GoogleFonts.dmSans(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15.5,
                                          color: Colors.black)),
                                  const SizedBox(height: 2),
                                  // tampilkan invoiceId jika ada, fallback doc.id
                                  Text('#$displayedId',
                                      style: GoogleFonts.dmSans(
                                          fontSize: 12.5,
                                          color: const Color(0xFF888888))),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _statusBadge(orderStatus),
                                // Badge tambahan untuk SHIPPED + confirmed
                                if (statusStr == 'SHIPPED') ...[
                                  Builder(
                                    builder: (context) {
                                      final deliveryProof = data['deliveryProof'] as Map<String, dynamic>?;
                                      final confirmed = deliveryProof?['confirmed'] as bool? ?? false;
                                      
                                      if (confirmed) {
                                        return Container(
                                          margin: const EdgeInsets.only(top: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF9E6),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: const Color(0xFFFFB800)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.hourglass_empty, size: 12, color: Color(0xFFFFB800)),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Menunggu Konfirmasi',
                                                style: GoogleFonts.dmSans(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(0xFFFFB800),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    _buildSeparator(),

                    // Tanggal & Waktu
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tanggal & Waktu',
                                style: GoogleFonts.dmSans(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                                createdAt != null ? _fmtDateTime(createdAt) : '-',
                                style: GoogleFonts.dmSans(
                                    fontSize: 13.5,
                                    color: const Color(0xFF828282))),
                          ],
                        ),
                      ),
                    ),

                    // Alamat pengiriman
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Alamat Pengiriman',
                                style: GoogleFonts.dmSans(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Builder(builder: (context) {
                              final textStyle = GoogleFonts.dmSans(
                                  fontSize: 13.5, color: const Color(0xFF232323));
                              if (isLongAddress && !_showFullAddress) {
                                final displayText = shippingAddress.substring(0, addressThreshold) + '... ';
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Flexible(
                                      child: Text.rich(
                                        TextSpan(
                                          text: displayText,
                                          style: textStyle,
                                          children: [
                                            WidgetSpan(
                                              alignment: PlaceholderAlignment.middle,
                                              child: GestureDetector(
                                                onTap: () =>
                                                    setState(() => _showFullAddress = true),
                                                child: Text('Lihat Selengkapnya',
                                                    style: GoogleFonts.dmSans(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w600,
                                                        color: const Color(0xFF2056D3))),
                                              ),
                                            ),
                                          ],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(shippingAddress, style: textStyle),
                                    if (isLongAddress && _showFullAddress)
                                      GestureDetector(
                                        onTap: () =>
                                            setState(() => _showFullAddress = false),
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 1),
                                          child: Text('Tutup',
                                              style: GoogleFonts.dmSans(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(0xFF2056D3))),
                                        ),
                                      ),
                                  ],
                                );
                              }
                            }),
                          ],
                        ),
                      ),
                    ),

                    _buildSeparator(),

                    // Produk list
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          children: items.map((it) {
                            final img = (it['imageUrl'] ?? it['image']) as String?;
                            final name = (it['name'] ?? '-') as String;
                            final note =
                                (it['variant'] ?? it['note'] ?? '') as String;
                            final price = ((it['price'] as num?) ?? 0).toInt();
                            final qty = ((it['qty'] as num?) ?? 0).toInt();
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(13),
                                    child: img != null && img.isNotEmpty
                                        ? Image.network(
                                            img,
                                            width: 56,
                                            height: 56,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => _imgPh(),
                                          )
                                        : _imgPh(),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: GoogleFonts.dmSans(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14.7)),
                                        if (note.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2.5),
                                            child: Text(note,
                                                style: GoogleFonts.dmSans(
                                                    fontSize: 12.5,
                                                    color: const Color(
                                                        0xFF888888))),
                                          ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text('Rp ${_rupiah(price)}',
                                              style: GoogleFonts.dmSans(
                                                  fontSize: 13.5,
                                                  color:
                                                      const Color(0xFF232323))),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 9, top: 3),
                                    child: Text('x$qty',
                                        style: GoogleFonts.dmSans(
                                            fontSize: 13.5,
                                            color:
                                                const Color(0xFF444444))),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    _buildSeparator(vertical: 18),

                    // Nota & metode pembayaran — SELALU tampil
                    if (showNota)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 11),
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9F9F9),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('Nota Pesanan',
                                        style: GoogleFonts.dmSans(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.3,
                                            color: const Color(0xFF222222))),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () {
                                        final txMap = _mapOrderToTransaction(
                                          displayedId: displayedId, // invoice tampilan
                                          orderDocId: orderDocId, // id asli doc
                                          data: data,
                                          buyerName: buyerName,
                                        );
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => TransactionDetailPage(
                                                transaction: txMap),
                                          ),
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 20),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      child: Row(
                                        children: [
                                          Text('Lihat',
                                              style: GoogleFonts.dmSans(
                                                  fontSize: 13.5,
                                                  color: const Color(
                                                      0xFF2056D3))),
                                          const Icon(Icons.receipt_long_rounded,
                                              color: Color(0xFF2056D3),
                                              size: 17),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text('Metode Pembayaran',
                                        style: GoogleFonts.dmSans(
                                            fontSize: 13,
                                            color: Color(0xFF828282))),
                                    const Spacer(),
                                    Text(methodText,
                                        style: GoogleFonts.dmSans(
                                            fontSize: 13.2,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 8),
                                    Image.asset(
                                      'assets/images/paymentlogo.png',
                                      height: 18,
                                      fit: BoxFit.contain,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Ringkasan biaya
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9F9F9),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 13),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildFeeRow('Subtotal', subtotal, bold: true),
                                  const SizedBox(height: 3),
                                  _buildFeeRow('Biaya Pengiriman', shippingFee,
                                      bold: true),
                                  // pajak/biaya lain tidak ditampilkan untuk seller
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F3F3),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 15),
                              child: Row(
                                children: [
                                  Text('Total',
                                      style: GoogleFonts.dmSans(
                                          fontSize: 16.3,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF232323))),
                                  const Spacer(),
                                  Text('Rp ${_rupiah(sellerTotal)}',
                                      style: GoogleFonts.dmSans(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16.5,
                                          color: const Color(0xFF232323))),
                                ],
                              ),
                            ),
                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ),

                    // Upload Delivery Proof Section (ONLY for SHIPPED + self-delivery + not confirmed)
                    if (statusStr == 'SHIPPED') ...[
                      SliverToBoxAdapter(
                        child: Builder(
                          builder: (context) {
                            final deliveryProof = data['deliveryProof'] as Map<String, dynamic>?;
                            final method = deliveryProof?['method'] as String?;
                            final confirmed = deliveryProof?['confirmed'] as bool? ?? false;

                            // HANYA tampil jika: method=self DAN belum confirmed
                            if (method != 'self' || confirmed) {
                              return const SizedBox.shrink();
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(color: Color(0xFFE6E6E6), thickness: 1),
                                  const SizedBox(height: 20),
                                  
                                  // Header
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF9E6),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFFFB800)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.camera_alt, color: Color(0xFFFFB800), size: 32),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Upload Bukti Pengiriman',
                                                style: GoogleFonts.dmSans(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(0xFF373E3C),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Wajib upload minimal 1 foto dokumentasi pengiriman',
                                                style: GoogleFonts.dmSans(
                                                  fontSize: 12,
                                                  color: const Color(0xFF777777),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 20),
                                  
                                  Row(
                                    children: [
                                      Text(
                                        'Foto Dokumentasi',
                                        style: GoogleFonts.dmSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFEEEE),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '1 Wajib, 2 Opsional',
                                          style: GoogleFonts.dmSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFFFF3449),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Image grid
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      ..._deliveryProofImages.asMap().entries.map((entry) {
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
                                            if (index == 0)
                                              Positioned(
                                                bottom: 4,
                                                left: 4,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'WAJIB',
                                                    style: GoogleFonts.dmSans(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: GestureDetector(
                                                onTap: () => _removeProofImage(index),
                                                child: Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: const BoxDecoration(
                                                    color: Colors.black54,
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
                                      
                                      if (_deliveryProofImages.length < 3)
                                        GestureDetector(
                                          onTap: _pickProofImage,
                                          child: Container(
                                            width: 100,
                                            height: 100,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF5F5F5),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: const Color(0xFF1C55C0),
                                                width: 2,
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.add_photo_alternate,
                                                  color: Color(0xFF1C55C0),
                                                  size: 32,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _deliveryProofImages.isEmpty ? 'Wajib' : 'Opsional',
                                                  style: GoogleFonts.dmSans(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: _deliveryProofImages.isEmpty 
                                                        ? const Color(0xFFFF3449)
                                                        : const Color(0xFF1C55C0),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 20),
                                  
                                  // Confirm Button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton.icon(
                                      onPressed: _uploading ? null : _uploadAndConfirmDelivery,
                                      icon: _uploading 
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              ),
                                            )
                                          : const Icon(Icons.check_circle, size: 24),
                                      label: Text(
                                        _uploading ? 'Mengupload...' : '✅ Konfirmasi Barang Sudah Dikirim',
                                        style: GoogleFonts.dmSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF28A745),
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: Colors.grey,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(100),
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 30),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ---------- mapper to TransactionDetailPage (VERSI SELLER) ----------
  Map<String, dynamic> _mapOrderToTransaction({
    required String displayedId, // invoice tampilan → gunakan invoiceId kalau ada
    required String orderDocId, // id asli dokumen (opsional)
    required Map<String, dynamic> data,
    required String buyerName,
  }) {
    final rawStatus =
        ((data['status'] ?? data['shippingAddress']?['status'] ?? 'PLACED') as String)
            .toUpperCase();

    // label untuk UI TransactionDetailPage
    String uiStatus;
    if (rawStatus == 'COMPLETED' ||
        rawStatus == 'DELIVERED' ||
        rawStatus == 'SUCCESS' ||
        rawStatus == 'SETTLED') {
      uiStatus = 'Sukses';
    } else if (rawStatus == 'CANCELLED' ||
        rawStatus == 'CANCELED' ||
        rawStatus == 'REJECTED' ||
        rawStatus == 'FAILED') {
      uiStatus = 'Gagal';
    } else {
      uiStatus = 'Tertahan'; // PLACED / ACCEPTED / SHIPPED
    }

    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final amounts = (data['amounts'] as Map<String, dynamic>?) ?? {};
    final subtotal = ((amounts['subtotal'] as num?) ?? 0).toInt();
    final shipping = ((amounts['shipping'] as num?) ?? 0).toInt();

    // VERSI SELLER:
    final tax = 0;
    final total = subtotal + shipping;

    final createdAt =
        (data['createdAt'] is Timestamp) ? (data['createdAt'] as Timestamp).toDate() : null;

    final ship = (data['shippingAddress'] as Map<String, dynamic>?) ?? {};
    final addressLabel = (ship['label'] ?? '-') as String;
    final addressText = (ship['addressText'] ?? ship['address'] ?? '-') as String;
    final phone = (ship['phone'] ?? '-') as String;

    final method = ((data['payment']?['method'] ?? 'abc_payment') as String).toUpperCase();

    return {
      'invoiceId': displayedId, // ditampilkan
      'orderDocId': orderDocId, // id dok asli (opsional)
      'status': uiStatus,
      'date': createdAt,
      'buyerName': buyerName,
      'shipping': {
        'recipient': buyerName,
        'addressLabel': addressLabel,
        'addressText': addressText,
        'phone': phone,
      },
      'paymentMethod': method,
      'items': items
          .map((it) {
            return {
              'name': (it['name'] ?? '-') as String,
              'qty': ((it['qty'] as num?) ?? 0).toInt(),
              'price': ((it['price'] as num?) ?? 0).toInt(),
              'variant': (it['variant'] ?? it['note'] ?? '') as String,
            };
          })
          .toList(),
      'amounts': {
        'subtotal': subtotal,
        'shipping': shipping,
        'tax': tax, // 0
        'total': total, // subtotal + shipping
      },
    };
  }

  // ---------- helpers ----------
  static OrderStatus _statusFrom(String s) {
    switch (s) {
      case 'COMPLETED':
      case 'SUCCESS':
        return OrderStatus.selesai;
      case 'DELIVERED':
      case 'SHIPPED':
        return OrderStatus.dikirim;
      case 'CANCELLED':
      case 'CANCELED':
      case 'REJECTED':
        return OrderStatus.dibatalkan;
      default:
        return OrderStatus.menunggu;
    }
  }

  static String _fmtDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y, $h12:$min $ampm';
    }

  static String _rupiah(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final fromRight = s.length - i;
      b.write(s[i]);
      if (fromRight > 1 && fromRight % 3 == 1) b.write('.');
    }
    return b.toString();
  }

  SliverToBoxAdapter _buildSeparator({double vertical = 0}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: vertical),
        child: const Divider(thickness: 1, color: Color(0xFFE6E6E6)),
      ),
    );
  }

  Widget _statusBadge(OrderStatus status) {
    String text;
    Color color;
    switch (status) {
      case OrderStatus.selesai:
        text = 'Selesai';
        color = const Color(0xFF24B47E);
        break;
      case OrderStatus.dibatalkan:
        text = 'Dibatalkan';
        color = const Color(0xFFFF3449);
        break;
      case OrderStatus.dikirim:
        text = 'Dikirim';
        color = const Color(0xFF2056D3);
        break;
      case OrderStatus.menunggu:
      default:
        text = 'Menunggu';
        color = const Color(0xFF828282);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w600, color: color, fontSize: 13.2)),
        ],
      ),
    );
  }

  Widget _imgPh() => Container(
        width: 56,
        height: 56,
        color: Colors.grey[200],
        child: const Icon(Icons.fastfood_rounded, size: 34, color: Colors.grey),
      );

  Widget _buildFeeRow(String title, int amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Text(title,
              style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: const Color(0xFF888888),
                  fontWeight: bold ? FontWeight.w500 : FontWeight.normal)),
          const Spacer(),
          Text('Rp ${_rupiah(amount)}',
              style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w500,
                  fontSize: 14.5,
                  color: const Color(0xFF222222))),
        ],
      ),
    );
  }
}

// Sticky header delegate
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;
  _StickyHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });
  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;
  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}
