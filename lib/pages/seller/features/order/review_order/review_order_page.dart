import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

// Popups lokal (sesuaikan path kalau berbeda)
import 'order_accepted_popup.dart';

// Nota detail (sesuaikan path kalau berbeda)
import 'package:pasma_apps/pages/seller/features/transaction/transaction_detail_page.dart';

// >>> NOTIFICATION SERVICE
import 'package:pasma_apps/data/services/notification_service.dart';

/// Palet tone untuk banner countdown
enum _BannerTone { info, success, warning }

class ReviewOrderPage extends StatefulWidget {
  final String orderId;
  const ReviewOrderPage({super.key, required this.orderId});

  @override
  State<ReviewOrderPage> createState() => _ReviewOrderPageState();
}

class _ReviewOrderPageState extends State<ReviewOrderPage> {
  bool _showFullAddress = false;
  
  // Shipping method selection
  String _selectedShippingMethod = 'courier'; // 'courier' or 'self'
  final _trackingNumberController = TextEditingController();
  final List<File> _proofImages = []; // Max 3 images (1 mandatory, 2 optional)

  @override
  void dispose() {
    _trackingNumberController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String newStatus) async {
    final updates = <String, dynamic>{
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Jika seller klik "Kirim Pesanan", set deadline:
    // PRODUCTION: 48 jam (2 hari) grace period start, 60 jam (2.5 hari) auto-complete
    if (newStatus.toUpperCase() == 'SHIPPED') {
      updates['shippedAt'] = FieldValue.serverTimestamp();
      final now = DateTime.now();
      updates['gracePeriodStartAt'] = Timestamp.fromDate(
        now.add(const Duration(hours: 48)), // PRODUCTION: 48 jam
      );
      updates['autoCompleteAt'] = Timestamp.fromDate(
        now.add(const Duration(hours: 60)), // PRODUCTION: 60 jam
      );
      updates['reminderSentAt'] = null; // Untuk trigger reminder di scheduler
    }

    await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .update(updates);
  }

  /// Ambil meta order untuk kebutuhan notifikasi
  Future<({String buyerId, String sellerId, String? invoiceId})>
      _fetchOrderMeta() async {
    final doc = await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .get();
    final data = doc.data() ?? {};
    final buyerId = (data['buyerId'] ?? '') as String;
    final sellerId = (data['sellerId'] ?? '') as String;
    final invoiceId = (data['invoiceId'] as String?);
    return (buyerId: buyerId, sellerId: sellerId, invoiceId: invoiceId);
  }

  Future<void> _acceptOrder() async {
    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast2',
      );
      await functions.httpsCallable('acceptOrder').call({
        'orderId': widget.orderId,
      });

      // notif → buyer
      final meta = await _fetchOrderMeta();
      if (meta.buyerId.isNotEmpty && meta.sellerId.isNotEmpty) {
        await NotificationService.instance.notifyOrderAccepted(
          buyerId: meta.buyerId,
          sellerId: meta.sellerId,
          orderId: widget.orderId,
          invoiceId: meta.invoiceId,
        );
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => const OrderAcceptedPopup(),
      );
      if (mounted) setState(() {});
    } on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? 'Gagal menerima pesanan.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menerima pesanan: $e')));
      }
    }
  }

  // Tolak pesanan → panggil cancelOrder agar dana buyer dikembalikan
  Future<void> _rejectOrder() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Tolak Pesanan?',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.bold)),
        content: Text('Anda yakin ingin menolak pesanan ini?',
            style: GoogleFonts.dmSans()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5B5B),
              foregroundColor: Colors.white,
            ),
            child: Text('Tolak',
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final functions = FirebaseFunctions.instanceFor(
          region: 'asia-southeast2',
        );
        await functions.httpsCallable('cancelOrder').call({
          'orderId': widget.orderId,
          'reason': 'Seller rejected',
        });

        // (opsional) kirim notif cancelled ke buyer jika punya endpoint-nya
        if (mounted) Navigator.pop(context); // keluar halaman
      } on FirebaseFunctionsException catch (e) {
        final msg = e.message ?? 'Gagal membatalkan pesanan.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal membatalkan pesanan: $e')));
        }
      }
    }
  }

  Future<void> _shipOrder() async {
    // Validasi berbeda untuk setiap metode
    if (_selectedShippingMethod == 'courier') {
      // KURIR: Wajib upload foto + resi SEBELUM kirim
      if (_proofImages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Minimal 1 foto dokumentasi wajib diupload untuk pengiriman kurir!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (_trackingNumberController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nomor resi wajib diisi untuk pengiriman kurir!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    // KIRIM SENDIRI: TIDAK perlu upload foto dulu, langsung kirim saja

    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Kirim Pesanan?',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.bold),
        ),
        content: Text(
          _selectedShippingMethod == 'courier'
              ? 'Pesanan akan dikirim melalui kurir dengan resi: ${_trackingNumberController.text.trim()}'
              : 'Pesanan akan dikirim sendiri oleh Anda.\n\nAnda bisa upload bukti pengiriman nanti di halaman detail pesanan.',
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
              backgroundColor: const Color(0xFF1C55C0),
            ),
            child: Text(
              'Ya, Kirim',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Upload foto (HANYA jika ada - untuk kurir)
      final List<String> uploadedUrls = [];
      if (_proofImages.isNotEmpty) {
        for (int i = 0; i < _proofImages.length; i++) {
          final file = _proofImages[i];
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final path = 'delivery_proofs/${widget.orderId}/${_selectedShippingMethod}_$timestamp\_$i.jpg';
          final ref = FirebaseStorage.instance.ref().child(path);
          
          await ref.putFile(file);
          final url = await ref.getDownloadURL();
          uploadedUrls.add(url);
        }
      }

      // Update order
      final updateData = {
        'status': 'SHIPPED',
        'shippedAt': FieldValue.serverTimestamp(),
        'gracePeriodStartAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 48)), // PRODUCTION: 48 jam
        ),
        'autoCompleteAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 60)), // PRODUCTION: 60 jam
        ),
        'reminderSentAt': null, // Untuk trigger reminder di scheduler
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Delivery proof (berbeda untuk setiap metode)
      if (_selectedShippingMethod == 'courier') {
        // Kurir: Simpan semua data sekarang
        updateData['deliveryProof'] = {
          'method': 'courier',
          'trackingNumber': _trackingNumberController.text.trim(),
          'proofImages': uploadedUrls,
          'uploadedAt': FieldValue.serverTimestamp(),
          'confirmed': true, // Langsung confirmed karena sudah upload
        };
      } else {
        // Kirim Sendiri: Tandai metode, foto diupload nanti
        updateData['deliveryProof'] = {
          'method': 'self',
          'trackingNumber': null,
          'proofImages': [], // Kosong dulu, upload nanti
          'uploadedAt': null,
          'confirmed': false, // Belum confirmed, nunggu upload foto
        };
      }

      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update(updateData);

      // Notif buyer
      final meta = await _fetchOrderMeta();
      if (meta.buyerId.isNotEmpty && meta.sellerId.isNotEmpty) {
        await NotificationService.instance.notifyOrderShipped(
          buyerId: meta.buyerId,
          sellerId: meta.sellerId,
          orderId: widget.orderId,
          invoiceId: meta.invoiceId,
        );
      }

      if (!mounted) return;
      
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(
            _selectedShippingMethod == 'courier' 
                ? 'Pesanan Berhasil Dikirim!' 
                : 'Pesanan Sedang Dikirim',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.bold),
          ),
          content: Text(
            _selectedShippingMethod == 'courier'
                ? 'Pesanan telah dikirim melalui kurir.\n\nPesanan dapat dilihat di tab "Dikirim".'
                : 'Pesanan telah ditandai dikirim.\n\n'
                  'Silakan buka pesanan di tab "Dikirim" untuk upload foto bukti pengiriman.',
            style: GoogleFonts.dmSans(),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // back to order list
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1C55C0),
              ),
              child: Text(
                'Mengerti',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengirim pesanan: $e')),
      );
    }
  }

  Future<void> _pickProofImage() async {
    if (_proofImages.length >= 3) {
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
        _proofImages.add(File(pickedFile.path));
      });
    }
  }

  Future<void> _removeProofImage(int index) async {
    setState(() {
      _proofImages.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderDocStream = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: orderDocStream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.hasData || !snap.data!.exists) {
              return Center(
                  child: Text('Pesanan tidak ditemukan',
                      style: GoogleFonts.dmSans()));
            }

            final data = snap.data!.data()!;
            final orderDocId = snap.data!.id;

            // invoice tampil (prioritas invoiceId)
            final rawInvoice = (data['invoiceId'] as String?)?.trim();
            final displayedId =
                (rawInvoice != null && rawInvoice.isNotEmpty) ? rawInvoice : orderDocId;

            final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
            final autoCancelAtTs = data['autoCancelAt'] as Timestamp?;
            final shipByAtTs = data['shipByAt'] as Timestamp?; // deadline dari server
            final buyerId = (data['buyerId'] ?? '') as String;

            final status = ((data['status'] ??
                        data['shippingAddress']?['status'] ??
                        'PLACED') as String)
                .toUpperCase();

            final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
            final amounts = (data['amounts'] as Map<String, dynamic>?) ?? {};
            final subtotal = ((amounts['subtotal'] as num?) ?? 0).toInt();
            final shipping = ((amounts['shipping'] as num?) ?? 0).toInt();
            final tax = ((amounts['tax'] as num?) ?? 0).toInt();
            final total = ((amounts['total'] as num?) ?? (subtotal + shipping + tax)).toInt();

            final shipAddr =
                (data['shippingAddress'] as Map<String, dynamic>?) ?? {};
            final addressLabel = (shipAddr['label'] ?? '-') as String;
            final addressText =
                (shipAddr['address'] ?? shipAddr['addressText'] ?? '-') as String;

            final method =
                ((data['payment']?['method'] ?? 'abc_payment') as String)
                    .toUpperCase();

            // Deadline menerima pesanan (prefer server timestamp)
            final DateTime? acceptDeadline = autoCancelAtTs != null
                ? autoCancelAtTs.toDate()
                : createdAt?.add(const Duration(days: 1));

            // Deadline kirim pesanan (48 jam setelah ACCEPTED) dari server
            final DateTime? shipDeadline = shipByAtTs?.toDate();

            // Buyer name (jika ada buyerId)
            if (buyerId.isEmpty) {
              return _buildOrderContent(
                buyerName: '-',
                createdAt: createdAt,
                addressLabel: addressLabel,
                addressText: addressText,
                items: items,
                subtotal: subtotal,
                shipping: shipping,
                tax: tax,
                total: total,
                method: method,
                data: data,
                displayedId: displayedId,
                orderDocId: orderDocId,
                status: status,
                acceptDeadline: acceptDeadline,
                shipDeadline: shipDeadline,
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(buyerId)
                  .snapshots(),
              builder: (context, userSnap) {
                final buyerName =
                    (userSnap.data?.data()?['name'] ?? '-') as String;
                return _buildOrderContent(
                  buyerName: buyerName,
                  createdAt: createdAt,
                  addressLabel: addressLabel,
                  addressText: addressText,
                  items: items,
                  subtotal: subtotal,
                  shipping: shipping,
                  tax: tax,
                  total: total,
                  method: method,
                  data: data,
                  displayedId: displayedId,
                  orderDocId: orderDocId,
                  status: status,
                  acceptDeadline: acceptDeadline,
                  shipDeadline: shipDeadline,
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar:
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snap) {
          final st = (snap.data?.data()?['status'] ?? 'PLACED')
              .toString()
              .toUpperCase();
          final showAcceptReject = st == 'PLACED';
          final showShip = st == 'ACCEPTED';

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
            child: Row(
              children: [
                if (showAcceptReject) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _rejectOrder,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF3449),
                        backgroundColor: const Color(0xFFFFE8E8),
                        side: const BorderSide(
                          color: Color(0xFFFF3449),
                          width: 1.2,
                        ),
                        padding:
                            const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text('Tolak',
                          style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _acceptOrder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2056D3),
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text('Terima',
                          style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ] else if (showShip) ...[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _shipOrder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2056D3),
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text('Kirim Pesanan',
                          style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ] else
                  const SizedBox.shrink(),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- content builder ----------
  Widget _buildOrderContent({
    required String buyerName,
    required DateTime? createdAt,
    required String addressLabel,
    required String addressText,
    required List<Map<String, dynamic>> items,
    required int subtotal,
    required int shipping,
    required int tax,
    required int total,
    required String method,
    required Map<String, dynamic> data,
    required String displayedId, // invoice tampilan
    required String orderDocId, // doc.id asli
    required String status,
    required DateTime? acceptDeadline,
    required DateTime? shipDeadline,
  }) {
    final isLong = addressText.length > 60;

    return CustomScrollView(
      slivers: [
        // Sticky header
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyHeaderDelegate(
            minHeight: 66,
            maxHeight: 66,
            child: Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 6),
              alignment: Alignment.centerLeft,
              child: Row(
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
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Text('Tinjau Pesanan',
                      style: GoogleFonts.dmSans(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),

        // header info
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text('Username Pembeli',
                    style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 2),
                Text(buyerName,
                    style: GoogleFonts.dmSans(
                        fontSize: 15.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('#$displayedId',
                    style: GoogleFonts.dmSans(
                        fontSize: 12.5, color: const Color(0xFF888888))),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFFE6E6E6)),
                const SizedBox(height: 8),
                Text('Tanggal & Waktu',
                    style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(createdAt != null ? _fmtDateTime(createdAt) : '-',
                    style: GoogleFonts.dmSans(
                        fontSize: 13.5, color: const Color(0xFF828282))),

                // Countdown: terima order
                if (status == 'PLACED' && acceptDeadline != null) ...[
                  const SizedBox(height: 10),
                  _countdownBanner(
                    title: 'Terima pesanan sebelum',
                    deadline: acceptDeadline,
                    caption:
                        'Jika melewati batas, pesanan otomatis dibatalkan oleh sistem.',
                    tone: _BannerTone.warning,
                  ),
                  const SizedBox(height: 10),
                ],

                // Countdown: kirim order
                if (status == 'ACCEPTED' && shipDeadline != null) ...[
                  const SizedBox(height: 10),
                  _countdownBanner(
                    title: 'Kirim pesanan sebelum',
                    deadline: shipDeadline,
                    caption:
                        'Pesanan harus dikirim dalam waktu 2 hari setelah diterima. '
                        'Jika melewati batas, pesanan dibatalkan otomatis oleh sistem.',
                    tone: _BannerTone.warning,
                  ),
                  const SizedBox(height: 10),
                ],

                const SizedBox(height: 13),
                Text('Alamat Pengiriman',
                    style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Builder(
                  builder: (_) {
                    final body = '$addressLabel, $addressText';
                    if (isLong && !_showFullAddress) {
                      final cut = body.substring(0, 60);
                      return Wrap(
                        children: [
                          Text('$cut...',
                              style: GoogleFonts.dmSans(fontSize: 13.5)),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _showFullAddress = true),
                            child: Text(' Lihat Selengkapnya',
                                style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF2056D3))),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(body,
                            style: GoogleFonts.dmSans(fontSize: 13.5)),
                        if (isLong)
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
                  },
                ),
                const SizedBox(height: 15),
                const Divider(color: Color(0xFFE6E6E6)),
              ],
            ),
          ),
        ),

        // list item
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: items.map((it) {
                final img = (it['imageUrl'] ?? it['image']) as String?;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.5),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: img != null && img.isNotEmpty
                            ? Image.network(
                                img,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _imgFallback(),
                              )
                            : _imgFallback(),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((it['name'] ?? '-') as String,
                                style: GoogleFonts.dmSans(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.7)),
                            if (((it['variant'] ?? it['note'] ?? '') as String)
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.5),
                                child: Text(
                                  (it['variant'] ?? it['note']) as String,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 12.5,
                                      color: const Color(0xFF888888)),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Rp ${_rupiah(((it['price'] as num?) ?? 0).toInt())}',
                                style: GoogleFonts.dmSans(
                                    fontSize: 13.5,
                                    color: const Color(0xFF232323)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 9, top: 3),
                        child: Text(
                          'x${((it['qty'] as num?) ?? 0).toInt()}',
                          style: GoogleFonts.dmSans(
                              fontSize: 13.5, color: const Color(0xFF444444))),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Nota & metode pembayaran
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 4, 13, 13),
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
                              fontSize: 15,
                              color: const Color(0xFF222222))),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          final txMap = _mapOrderToTransaction(
                            displayedId: displayedId,
                            orderDocId: orderDocId,
                            data: data,
                            buyerName: buyerName,
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  TransactionDetailPage(transaction: txMap),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Text('Lihat',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13.5,
                                  color: const Color(0xFF2056D3),
                                )),
                            const Icon(Icons.receipt_long_rounded,
                                color: Color(0xFF2056D3), size: 17),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Metode Pembayaran',
                          style: GoogleFonts.dmSans(
                              fontSize: 13, color: const Color(0xFF828282))),
                      const Spacer(),
                      Row(
                        children: [
                          Text(
                            method == 'ABC_PAYMENT' ? 'PASMA Payment' : method,
                            style: GoogleFonts.dmSans(
                                fontSize: 13.2, fontWeight: FontWeight.w600),
                          ),
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
                ],
              ),
            ),
          ),
        ),

        // subtotal / total
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
                      _feeRow('Subtotal', subtotal),
                      const SizedBox(height: 3),
                      _feeRow('Biaya Pengiriman', shipping),
                      const SizedBox(height: 3),
                      _feeRow('Pajak & Biaya Lainnya', tax),
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
                              fontSize: 16.3, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('Rp ${_rupiah(total)}',
                          style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.bold, fontSize: 16.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),

        // Shipping Method & Documentation (ONLY SHOW IF STATUS == ACCEPTED)
        if (status == 'ACCEPTED') ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Color(0xFFE6E6E6), thickness: 1),
                  const SizedBox(height: 20),
                  
                  Text(
                    'Metode Pengiriman',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Radio buttons
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: 'courier',
                          groupValue: _selectedShippingMethod,
                          onChanged: (value) {
                            setState(() {
                              _selectedShippingMethod = value!;
                            });
                          },
                          title: Text(
                            'Pakai Kurir (Gojek/Grab/JNE/dll)',
                            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Menggunakan jasa kurir pengiriman',
                            style: GoogleFonts.dmSans(fontSize: 12),
                          ),
                          activeColor: const Color(0xFF1C55C0),
                        ),
                        const Divider(height: 1),
                        RadioListTile<String>(
                          value: 'self',
                          groupValue: _selectedShippingMethod,
                          onChanged: (value) {
                            setState(() {
                              _selectedShippingMethod = value!;
                            });
                          },
                          title: Text(
                            'Kirim Sendiri',
                            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Mengantar langsung ke alamat pembeli',
                            style: GoogleFonts.dmSans(fontSize: 12),
                          ),
                          activeColor: const Color(0xFF1C55C0),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Nomor Resi (only for courier)
                  if (_selectedShippingMethod == 'courier') ...[
                    Text(
                      'Nomor Resi',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _trackingNumberController,
                      decoration: InputDecoration(
                        hintText: 'Masukkan nomor resi',
                        hintStyle: GoogleFonts.dmSans(fontSize: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF1C55C0), width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Foto Dokumentasi - HANYA UNTUK KURIR
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
                    const SizedBox(height: 8),
                    Text(
                      'Upload foto bukti serah kurir, struk, atau dokumentasi pengiriman',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: const Color(0xFF777777),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Image grid - HANYA UNTUK KURIR
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                      // Display uploaded images
                      ..._proofImages.asMap().entries.map((entry) {
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
                            // Badge mandatory/optional
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
                            // Remove button
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
                      
                      // Add button (if < 3 images)
                      if (_proofImages.length < 3)
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
                                style: BorderStyle.solid,
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
                                  _proofImages.isEmpty ? 'Wajib' : 'Opsional',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _proofImages.isEmpty 
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
                  
                  const SizedBox(height: 30),
                ], // Close if courier

                  // Info untuk Kirim Sendiri
                  if (_selectedShippingMethod == 'self') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9E6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFB800)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFFFFB800), size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Upload Bukti Nanti',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF373E3C),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Anda bisa upload foto dokumentasi pengiriman nanti di halaman Lacak Pesanan setelah barang dikirim ke pembeli.',
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
                    const SizedBox(height: 30),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------- helpers ----------
  static Widget _imgFallback() => Container(
        width: 56,
        height: 56,
        color: Colors.grey[200],
        child:
            const Icon(Icons.fastfood_rounded, size: 34, color: Colors.grey),
      );

  static Widget _feeRow(String title, int amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Text(title,
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: const Color(0xFF888888))),
          const Spacer(),
          Text('Rp ${_rupiah(amount)}',
              style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w500, fontSize: 14.5)),
        ],
      ),
    );
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

  static String _fmtDateTime(DateTime dt) {
    // 05/07/2025, 8:00 PM
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y, $hour12:$min $ampm';
  }

  // ======== Countdown Banner (reusable) ========
  Widget _countdownBanner({
    required String title,
    required DateTime deadline,
    String? caption,
    _BannerTone tone = _BannerTone.info,
  }) {
    final Color bg, border, textColor, iconBg;
    switch (tone) {
      case _BannerTone.success:
        bg = const Color(0xFFF1FFF6);
        border = const Color(0xFF28A745);
        textColor = const Color(0xFF166534);
        iconBg = const Color(0xFFE8FFF0);
        break;
      case _BannerTone.warning:
        bg = const Color(0xFFFFFBF1);
        border = const Color(0xFFEAB600);
        textColor = const Color(0xFF6B4E00);
        iconBg = const Color(0xFFFFF3C4);
        break;
      case _BannerTone.info:
      default:
        bg = const Color(0xFFF1F7FF);
        border = const Color(0xFF1976D2);
        textColor = const Color(0xFF0C3C78);
        iconBg = const Color(0xFFE7F1FF);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration:
                BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: const Icon(Icons.access_time_rounded,
                size: 18, color: Color(0xFF666666)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StreamBuilder<DateTime>(
              stream: Stream<DateTime>.periodic(
                const Duration(seconds: 1),
                (_) => DateTime.now(),
              ),
              builder: (_, tick) {
                final now = tick.data ?? DateTime.now();
                final remaining = deadline.difference(now);
                final over = remaining.isNegative;
                final text =
                    over ? 'Waktu habis' : _fmtRemaining(remaining);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$title ${_fmtDateTime(deadline)}',
                        style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.2,
                            color: textColor)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: border, width: 1.1),
                          ),
                          child: Text(
                            over
                                ? 'Akan dibatalkan oleh sistem'
                                : 'Sisa waktu: $text',
                            style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w600,
                                fontSize: 12.2,
                                color: textColor),
                          ),
                        ),
                      ],
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 6),
                      Text(caption,
                          style: GoogleFonts.dmSans(
                              fontSize: 12, color: textColor)),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtRemaining(Duration d) {
    var secs = d.inSeconds;
    if (secs < 0) secs = 0;
    final days = secs ~/ 86400;
    secs %= 86400;
    final hrs = secs ~/ 3600;
    secs %= 3600;
    final mins = secs ~/ 60;
    secs %= 60;
    if (days > 0) return '${days}h ${hrs}j ${mins}m ${secs}s';
    if (hrs > 0) return '${hrs}j ${mins}m ${secs}s';
    if (mins > 0) return '${mins}m ${secs}s';
    return '${secs}s';
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
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(
          covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

// ---------------- MAPPER: order doc -> map untuk TransactionDetailPage (VERSI SELLER) ----------------
Map<String, dynamic> _mapOrderToTransaction({
  required String displayedId, // invoice tampilan (invoiceId/doc.id)
  required String orderDocId,  // doc.id asli
  required Map<String, dynamic> data,
  required String buyerName,
}) {
  final rawStatus = ((data['status'] ??
          data['shippingAddress']?['status'] ??
          'PLACED') as String)
      .toUpperCase();

  // label status untuk nota
  String labelStatus;
  if (rawStatus == 'COMPLETED' ||
      rawStatus == 'DELIVERED' ||
      rawStatus == 'SETTLED' ||
      rawStatus == 'SUCCESS') {
    labelStatus = 'Sukses';
  } else if (rawStatus == 'CANCELLED' ||
      rawStatus == 'CANCELED' ||
      rawStatus == 'REJECTED' ||
      rawStatus == 'FAILED') {
    labelStatus = 'Gagal';
  } else {
    labelStatus = 'Tertahan';
  }

  final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
  final amounts = (data['amounts'] as Map<String, dynamic>?) ?? {};
  final subtotal = ((amounts['subtotal'] as num?) ?? 0).toInt();
  final shipping = ((amounts['shipping'] as num?) ?? 0).toInt();
  final tax = ((amounts['tax'] as num?) ?? 0).toInt();
  final total =
      ((amounts['total'] as num?) ?? (subtotal + shipping + tax)).toInt();

  final createdAt = (data['createdAt'] is Timestamp)
      ? (data['createdAt'] as Timestamp).toDate()
      : null;

  final ship = (data['shippingAddress'] as Map<String, dynamic>?) ?? {};
  final addressLabel = (ship['label'] ?? '-') as String;
  final addressText = (ship['addressText'] ?? ship['address'] ?? '-') as String;
  final phone = (ship['phone'] ?? '-') as String;

  final method =
      ((data['payment']?['method'] ?? 'abc_payment') as String).toUpperCase();

  return {
    'invoiceId': displayedId,
    'orderDocId': orderDocId,
    'status': labelStatus,
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
        .map((it) => {
              'name': (it['name'] ?? '-') as String,
              'qty': ((it['qty'] as num?) ?? 0).toInt(),
              'price': ((it['price'] as num?) ?? 0).toInt(),
              'variant': (it['variant'] ?? it['note'] ?? '') as String,
            })
        .toList(),
    'amounts': {
      'subtotal': subtotal,
      'shipping': shipping,
      'tax': tax,
      'total': total,
    },
  };
}
