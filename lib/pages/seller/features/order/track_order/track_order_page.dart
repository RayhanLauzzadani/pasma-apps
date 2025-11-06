import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

import 'package:pasma_apps/pages/seller/features/chat/chat_detail_page.dart';
// Ganti path ini kalau lokasi file berbeda
import 'package:pasma_apps/pages/seller/features/transaction/transaction_detail_page.dart';

class TrackOrderPageSeller extends StatefulWidget {
  final String orderId;
  const TrackOrderPageSeller({super.key, required this.orderId});

  @override
  State<TrackOrderPageSeller> createState() => _TrackOrderPageSellerState();
}

class _TrackOrderPageSellerState extends State<TrackOrderPageSeller> {
  bool _isAddressExpanded = false;
  final List<File> _deliveryProofImages = [];
  bool _uploading = false;
  bool _isPicking = false; // Flag to prevent multiple image picker calls

  Future<void> _pickProofImage() async {
    // Prevent multiple calls
    if (_isPicking) return;
    
    if (_deliveryProofImages.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maksimal 3 foto dokumentasi')),
      );
      return;
    }

    setState(() => _isPicking = true);

    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memilih foto: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
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

      // Get order data for buyer notification
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .get();
      
      final orderData = orderDoc.data();
      final buyerId = orderData?['buyerId'] as String?;
      final invoiceId = orderData?['invoiceId'] as String? ?? widget.orderId;

      // PRODUCTION: 48 jam normal + 12 jam grace period = 60 jam total auto-complete
      final now = DateTime.now();
      final gracePeriodStart = now.add(const Duration(hours: 48)); // Mulai grace period setelah 48 jam
      final autoCompleteTime = now.add(const Duration(hours: 60)); // Auto-complete setelah 60 jam

      // Update deliveryProof di order
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
        'deliveryProof.proofImages': uploadedUrls,
        'deliveryProof.uploadedAt': FieldValue.serverTimestamp(),
        'deliveryProof.confirmed': true,
        'gracePeriodStartAt': Timestamp.fromDate(gracePeriodStart),
        'autoCompleteAt': Timestamp.fromDate(autoCompleteTime),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Send notification to buyer
      if (buyerId != null && buyerId.isNotEmpty) {
        await _sendNotificationToBuyer(
          buyerId: buyerId,
          title: 'Pesanan Sudah Sampai! 📦',
          body: 'Penjual telah mengantarkan pesanan #$invoiceId ke alamat Anda. '
                'Silakan konfirmasi penerimaan barang.',
          orderId: widget.orderId,
        );
      }

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

  int _currentStepIndex(String status) {
    switch (status.toUpperCase()) {
      case 'SHIPPED':
        return 1;
      case 'DELIVERED':
      case 'COMPLETED':
      case 'SUCCESS':
        return 2;
      case 'PLACED':
      case 'ACCEPTED':
      default:
        return 0;
    }
  }

  String _step1Title(String status) {
    return status.toUpperCase() == 'PLACED'
        ? 'Menunggu Seller menerima pesanan'
        : 'Produk disiapkan Toko';
  }

  Future<void> _sendNotificationToBuyer({
    required String buyerId,
    required String title,
    required String body,
    required String orderId,
  }) async {
    try {
      // Get buyer's FCM token
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(buyerId)
          .get();
      
      final fcmToken = userDoc.data()?['fcmToken'] as String?;
      
      if (fcmToken != null && fcmToken.isNotEmpty) {
        // Create notification document
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': buyerId,
          'title': title,
          'body': body,
          'orderId': orderId,
          'type': 'order_delivered',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        // Note: Actual FCM push will be handled by Cloud Function
        // or you can implement FCM HTTP API call here
        print('Notification sent to buyer: $buyerId');
      }
    } catch (e) {
      print('Failed to send notification: $e');
      // Don't throw error, notification is not critical
    }
  }

  Future<void> _openChat({
    required String buyerId,
    required String buyerName,
    required String buyerAvatar,
  }) async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) return;

    // Ambil storeId seller
    final sellerDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final storeId = (sellerDoc.data()?['storeId'] ?? '').toString();
    if (storeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Toko anda belum terhubung.')),
      );
      return;
    }

    // Cek apakah chat sudah ada
    final existSnap = await FirebaseFirestore.instance
        .collection('chats')
        .where('shopId', isEqualTo: storeId)
        .where('buyerId', isEqualTo: buyerId)
        .limit(1)
        .get();

    String chatId;
    if (existSnap.docs.isNotEmpty) {
      chatId = existSnap.docs.first.id;
    } else {
      // Buat chat baru
      final ref = FirebaseFirestore.instance.collection('chats').doc();
      await ref.set({
        'shopId': storeId,
        'buyerId': buyerId,
        'buyerName': buyerName,
        'buyerAvatar': buyerAvatar,
        'lastMessage': '',
        'lastTimestamp': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      chatId = ref.id;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SellerChatDetailPage(
          chatId: chatId,
          buyerId: buyerId,
          buyerName: buyerName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docStream =
        FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.white,
          automaticallyImplyLeading: false,
          primary: false,
          flexibleSpace: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.only(left: 20, top: 40, bottom: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 37,
                      height: 37,
                      decoration: const BoxDecoration(
                          color: Color(0xFF1C55C0), shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Lacak Pesanan',
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF373E3C),
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Center(
                child: Text('Pesanan tidak ditemukan', style: GoogleFonts.dmSans()));
          }

          final data = snap.data!.data()!;
          final status = (data['status'] ?? 'PLACED') as String;

          // === invoiceId tampilan (fallback ke doc.id)
          final realDocId = snap.data!.id;
          final rawInvoice = (data['invoiceId'] as String?)?.trim();
          final displayedInvoice =
              (rawInvoice != null && rawInvoice.isNotEmpty) ? rawInvoice : realDocId;

          final storeName = (data['storeName'] ?? '-') as String;
          final buyerId = (data['buyerId'] ?? '') as String;

          final addressMap = (data['shippingAddress'] as Map<String, dynamic>?) ?? {};
          final addressLabel = (addressMap['label'] ?? '-') as String;
          final addressText =
              (addressMap['addressText'] ?? addressMap['address'] ?? '-') as String;

          final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
          final stepIndex = _currentStepIndex(status);
          final step1Title = _step1Title(status);

          // amounts + method dinamis
          final amounts = (data['amounts'] as Map<String, dynamic>?) ?? {};
          final subtotal = ((amounts['subtotal'] as num?) ?? 0).toInt();
          final shipping = ((amounts['shipping'] as num?) ?? 0).toInt();
          // final tax = ((amounts['tax'] as num?) ?? 0).toInt(); // tidak dipakai di seller
          // final total = ((amounts['total'] as num?) ?? (subtotal + shipping + tax)).toInt();

          final methodRaw =
              ((data['payment']?['method'] ?? 'abc_payment') as String).toUpperCase();
          final methodText = methodRaw == 'ABC_PAYMENT' ? 'PASMA Payment' : methodRaw;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: buyerId.isEmpty
                ? const Stream.empty()
                : FirebaseFirestore.instance.collection('users').doc(buyerId).snapshots(),
            builder: (context, buyerSnap) {
              final buyer = buyerSnap.data?.data();
              final buyerName = (buyer?['name'] ?? '-') as String;
              final buyerAvatar = (buyer?['photoUrl'] ?? '') as String;

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text('Status Pesanan',
                        style: GoogleFonts.dmSans(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF373E3C))),
                    const SizedBox(height: 12),

                    // 1) Disiapkan toko -> subjudul = nama toko
                    _statusItem(
                      title: step1Title,
                      subtitle: storeName,
                      asset: 'assets/icons/store.svg',
                      activeColor: const Color(0xFFDC3545),
                      isReached: stepIndex >= 0,
                    ),
                    const SizedBox(height: 6),
                    _moreIcon(),
                    const SizedBox(height: 6),

                    // 2) Sedang dikirim -> TANPA subjudul
                    _statusItem(
                      title: 'Produk Sedang Dikirim',
                      subtitle: '',
                      asset: 'assets/icons/deliver.svg',
                      activeColor: const Color(0xFF1C55C0),
                      isReached: stepIndex >= 1,
                    ),
                    const SizedBox(height: 6),
                    _moreIcon(),
                    const SizedBox(height: 6),

                    // 3) Sampai tujuan -> subjudul = nama buyer
                    _statusItem(
                      title: 'Produk Sampai Tujuan',
                      subtitle: buyerName,
                      asset: 'assets/icons/circle_check.svg',
                      activeColor: const Color(0xFF28A745),
                      isReached: stepIndex >= 2,
                    ),

                    // Countdown banner if waiting for buyer confirmation
                    if (status.toUpperCase() == 'SHIPPED') ...[
                      Builder(
                        builder: (context) {
                          final deliveryProof = data['deliveryProof'] as Map<String, dynamic>?;
                          final confirmed = deliveryProof?['confirmed'] as bool? ?? false;
                          final autoCompleteAt = data['autoCompleteAt'] as Timestamp?;

                          if (confirmed && autoCompleteAt != null) {
                            return Column(
                              children: [
                                const SizedBox(height: 20),
                                _buildCountdownBanner(autoCompleteAt.toDate()),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],

                    const SizedBox(height: 16),
                    _divider(),
                    const SizedBox(height: 16),

                    // ===== Detail Pesanan (POV Seller) =====
                    Text('Detail Pesanan',
                        style: GoogleFonts.dmSans(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF373E3C))),
                    const SizedBox(height: 12),

                    // Username Pembeli
                    Text('Username Pembeli',
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF373E3C))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // foto profil buyer
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: buyerAvatar.isNotEmpty
                              ? Image.network(
                                  buyerAvatar,
                                  width: 60,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _defaultAvatar(),
                                )
                              : _defaultAvatar(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(buyerName,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF373E3C))),
                              const SizedBox(height: 4),
                              // tampilkan invoice (fallback doc.id)
                              Text('#$displayedInvoice',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 12, color: const Color(0xFF9A9A9A))),
                            ],
                          ),
                        ),
                        // tombol chat
                        GestureDetector(
                          onTap: () => _openChat(
                            buyerId: buyerId,
                            buyerName: buyerName,
                            buyerAvatar: buyerAvatar,
                          ),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                                color: Color(0xFF1C55C0), shape: BoxShape.circle),
                            child: Center(
                              child: SvgPicture.asset('assets/icons/chat.svg',
                                  width: 20, height: 20, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    _divider(),
                    const SizedBox(height: 12),

                    // Alamat Pengiriman
                    Text('Alamat Pengiriman',
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF373E3C))),
                    const SizedBox(height: 6),
                    Text(
                      _isAddressExpanded
                          ? '$addressLabel, $addressText'
                          : '$addressLabel, ${addressText.length > 38 ? "${addressText.substring(0, 38)}..." : addressText}',
                      style: GoogleFonts.dmSans(
                          fontSize: 14, color: const Color(0xFF9A9A9A))),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () =>
                          setState(() => _isAddressExpanded = !_isAddressExpanded),
                      child: Text(
                        _isAddressExpanded
                            ? 'Lihat Lebih Sedikit'
                            : 'Lihat Selengkapnya',
                        style: GoogleFonts.dmSans(
                            fontSize: 14, color: const Color(0xFF1C55C0))),
                    ),

                    const SizedBox(height: 12),
                    _divider(),
                    const SizedBox(height: 12),

                    // Produk yang Dipesan
                    Text('Produk yang Dipesan',
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF373E3C))),
                    const SizedBox(height: 12),

                    ...items.map((it) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _productRow(
                            name: (it['name'] ?? '-') as String,
                            subtitle: (it['variant'] ?? '') as String,
                            price: ((it['price'] as num?) ?? 0),
                            qty: ((it['qty'] as num?) ?? 0),
                            imageUrl:
                                (it['imageUrl'] ?? it['image'] ?? '') as String,
                          ),
                        )),

                    const SizedBox(height: 14),
                    _divider(),
                    const SizedBox(height: 14),

                    // Nota Pesanan (dinamis + tombol Lihat) — VERSI SELLER
                    _notaPesananCard(
                      methodText: methodText,
                      onView: () {
                        final txMap = _mapOrderToTransaction(
                          displayedId: displayedInvoice,
                          orderDocId: realDocId,
                          data: data,
                          buyerName: buyerName,
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                TransactionDetailPage(transaction: txMap),
                          ),
                        );
                      },
                      subtotal: subtotal,
                      shipping: shipping,
                      tax: 0, // seller tidak menampilkan pajak
                      total: subtotal + shipping, // total versi seller
                    ),

                    // Upload Delivery Proof Section (ONLY for SHIPPED + self-delivery + not confirmed)
                    if (status.toUpperCase() == 'SHIPPED') ...[
                      Builder(
                        builder: (context) {
                          final deliveryProof = data['deliveryProof'] as Map<String, dynamic>?;
                          final method = deliveryProof?['method'] as String?;
                          final confirmed = deliveryProof?['confirmed'] as bool? ?? false;

                          // HANYA tampil jika: method=self DAN belum confirmed
                          if (method != 'self' || confirmed) {
                            return const SizedBox.shrink();
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 20),
                              _divider(),
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
                            ],
                          );
                        },
                      ),
                    ],

                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ---------- UI helpers ----------
  Widget _statusItem({
    required String title,
    required String subtitle,
    required String asset,
    required Color activeColor,
    required bool isReached,
  }) {
    final color = isReached ? activeColor : const Color(0xFFBABABA);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset(asset, width: 26, height: 26, color: color),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF373E3C))),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: const Color(0xFF9A9A9A))),
          ],
        ),
      ],
    );
  }

  Widget _defaultAvatar() => Container(
        width: 60,
        height: 50,
        color: const Color(0xFFEDEDED),
        child: const Icon(Icons.person, color: Color(0xFF1C55C0), size: 26),
      );

  Widget _moreIcon() => Row(
        children: [
          SvgPicture.asset('assets/icons/more.svg',
              width: 20, height: 20, color: const Color(0xFFBABABA)),
        ],
      );

  Widget _divider() => Container(color: const Color(0xFFF2F2F3), height: 1);

  Widget _buildCountdownBanner(DateTime deadline) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, _) {
        final now = DateTime.now();
        final remaining = deadline.difference(now);

        if (remaining.isNegative) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF4CAF50), width: 2),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pesanan Akan Selesai Otomatis',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dana akan segera dicairkan ke saldo Anda',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final minutes = remaining.inMinutes;
        final seconds = remaining.inSeconds % 60;
        final timeStr = '${minutes}m ${seconds}s';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9E6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFB800), width: 2),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.hourglass_empty, color: Color(0xFFFFB800), size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '⏱️ Menunggu Konfirmasi Pembeli',
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF373E3C),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      'Auto-Complete Countdown',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: const Color(0xFF777777),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timeStr,
                      style: GoogleFonts.dmSans(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFFFB800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Pesanan akan otomatis selesai jika pembeli tidak konfirmasi. Dana akan dicairkan ke saldo Anda.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: const Color(0xFF777777),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _productRow({
    required String name,
    required String subtitle,
    required num price,
    required num qty,
    required String imageUrl,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 95,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFEDEDED),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.image, color: Colors.grey),
                )
              : const Icon(Icons.image, color: Colors.grey),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF373E3C))),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle,
                    style: GoogleFonts.dmSans(
                        fontSize: 14, color: const Color(0xFF777777))),
              ],
              const SizedBox(height: 8),
              Text('Rp ${_formatRupiah(price.toInt())}',
                  style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF373E3C))),
            ],
          ),
        ),
        Text('x${qty.toInt()}',
            style:
                GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF9A9A9A))),
      ],
    );
  }

  Widget _notaPesananCard({
    required String methodText,
    required VoidCallback onView,
    required int subtotal,
    required int shipping,
    required int tax, // akan disembunyikan bila 0
    required int total,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // header + tombol lihat
          Row(
            children: [
              Text('Nota Pesanan',
                  style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF222222))),
              const Spacer(),
              TextButton.icon(
                onPressed: onView,
                icon: const Icon(Icons.receipt_long_rounded,
                    size: 18, color: Color(0xFF2056D3)),
                label: Text('Lihat',
                    style: GoogleFonts.dmSans(
                        fontSize: 13.5, color: Color(0xFF2056D3))),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // method
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Metode Pembayaran',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: Color(0xFF828282))),
              Row(
                children: [
                  Text(methodText,
                      style: GoogleFonts.dmSans(
                          fontSize: 13.2, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Image.asset('assets/images/paymentlogo.png', height: 18),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ringkasan singkat
          _feeRow('Subtotal', subtotal),
          const SizedBox(height: 4),
          _feeRow('Biaya Pengiriman', shipping),
          if (tax > 0) ...[
            const SizedBox(height: 4),
            _feeRow('Pajak & Biaya Lainnya', tax),
          ],
          const Divider(height: 16, color: Color(0xFFE5E5E5)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: GoogleFonts.dmSans(
                      fontSize: 15.5, fontWeight: FontWeight.w700)),
              Text('Rp ${_formatRupiah(total)}',
                  style: GoogleFonts.dmSans(
                      fontSize: 15.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _feeRow(String title, int amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style:
                GoogleFonts.dmSans(fontSize: 13.5, color: const Color(0xFF777777))),
        Text('Rp ${_formatRupiahStatic(amount)}',
            style: GoogleFonts.dmSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF373E3C))),
      ],
    );
  }

  String _formatRupiah(int v) => _formatRupiahStatic(v);
  static String _formatRupiahStatic(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idxFromRight = s.length - i;
      b.write(s[i]);
      if (idxFromRight > 1 && idxFromRight % 3 == 1) b.write('.');
    }
    return b.toString();
  }

  // Map dokumen order → map untuk TransactionDetailPage (VERSI SELLER)
  Map<String, dynamic> _mapOrderToTransaction({
    required String displayedId, // invoice tampilan
    required String orderDocId, // doc.id asli (opsional)
    required Map<String, dynamic> data,
    required String buyerName,
  }) {
    final rawStatus =
        ((data['status'] ?? data['shippingAddress']?['status'] ?? 'PLACED') as String)
            .toUpperCase();

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
      labelStatus = 'Tertahan'; // PLACED / ACCEPTED / SHIPPED
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
        'tax': tax, // 0
        'total': total, // subtotal + shipping
      },
    };
  }
}
