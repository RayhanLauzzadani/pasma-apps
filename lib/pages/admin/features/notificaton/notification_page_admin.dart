import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Detail approval toko
import 'package:abc_e_mart/admin/features/approval/store/admin_store_approval_detail_page.dart';
// Detail approval payment (topup & withdraw)
import 'package:abc_e_mart/admin/features/approval/payment/admin_payment_approval_detail_page.dart';
// Detail approval iklan
import 'package:abc_e_mart/admin/features/approval/ad/admin_ad_approval_detail_page.dart';
import 'package:abc_e_mart/seller/data/models/ad.dart';

class NotificationPageAdmin extends StatelessWidget {
  const NotificationPageAdmin({super.key});

  /// Style ikon berdasarkan `type` atau fallback `title`
  Map<String, dynamic> _notifStyle({String? type, String? title}) {
    final lowerType = (type ?? '').toLowerCase();
    final lowerTitle = (title ?? '').toLowerCase();

    // ---- Payment: Topup (oranye)
    if (lowerType.startsWith('wallet_topup') || lowerTitle.contains('isi saldo')) {
      return {
        "svg": null,
        "iconData": Icons.account_balance_wallet_rounded,
        "iconColor": const Color(0xFFF4C21B),
        "bgColor": const Color(0x33F4C21B),
      };
    }

    // ---- Payment: Withdraw (biru/indigo)
    if (lowerType.startsWith('wallet_withdraw') ||
        lowerType.startsWith('seller_withdraw') ||
        lowerTitle.contains('tarik saldo') ||
        lowerTitle.contains('pencairan')) {
      return {
        "svg": null,
        "iconData": Icons.account_balance_wallet_rounded,
        "iconColor": const Color(0xFF1C55C0),
        "bgColor": const Color(0x331C55C0),
      };
    }

    // ---- Toko
    if (lowerTitle.contains('toko')) {
      return {
        "svg": 'assets/icons/store.svg',
        "iconData": null,
        "iconColor": const Color(0xFF28A745),
        "bgColor": const Color(0xFFEDF9F1),
      };
    }

    // ---- Produk
    if (lowerTitle.contains('produk')) {
      return {
        "svg": 'assets/icons/box.svg',
        "iconData": null,
        "iconColor": const Color(0xFF1C55C0),
        "bgColor": const Color(0x331C55C0),
      };
    }

    // ---- Iklan
    if (lowerTitle.contains('iklan')) {
      return {
        "svg": 'assets/icons/megaphone.svg',
        "iconData": null,
        "iconColor": const Color(0xFFB95FD0),
        "bgColor": const Color(0x33B95FD0),
      };
    }

    // Default
    return {
      "svg": null,
      "iconData": Icons.notifications,
      "iconColor": const Color(0xFF9AA0A6),
      "bgColor": const Color(0xFFEDEDED),
    };
  }

  bool _looksLikeAd(Map<String, dynamic> data) {
    final type = (data['type'] as String?)?.toLowerCase() ?? '';
    final title = (data['title'] as String?)?.toLowerCase() ?? '';
    return type.contains('ad') || type.contains('iklan') || title.contains('iklan');
  }

  String? _extractAdId(Map<String, dynamic> data) {
    // coba ambil dari beberapa kemungkinan field
    final keys = [
      'adApplicationId',
      'adId',
      'adDocId',
      'docId',
      'applicationId',
    ];
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  Future<void> _openAdById(BuildContext context, String adId) async {
    // loader ringan
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final snap = await FirebaseFirestore.instance
          .collection('adsApplication')
          .doc(adId)
          .get();

      Navigator.of(context, rootNavigator: true).pop(); // close loader

      if (!snap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajuan iklan tidak ditemukan.')),
        );
        return;
      }
      final ad = AdApplication.fromFirestore(snap);
      // ignore: use_build_context_synchronously
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AdminAdApprovalDetailPage(ad: ad)),
      );
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka ajuan iklan: $e')),
      );
    }
  }

  Future<void> _openLatestPendingAdFallback(BuildContext context) async {
    // loader ringan
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final qs = await FirebaseFirestore.instance
          .collection('adsApplication')
          .where('status', whereIn: ['Menunggu', 'menunggu', 'pending'])
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      Navigator.of(context, rootNavigator: true).pop(); // close loader

      if (qs.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada ajuan iklan berstatus menunggu.')),
        );
        return;
      }

      final ad = AdApplication.fromFirestore(qs.docs.first);
      // ignore: use_build_context_synchronously
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AdminAdApprovalDetailPage(ad: ad)),
      );
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat ajuan iklan: $e')),
      );
    }
  }

  Future<void> _handleTap({
    required BuildContext context,
    required DocumentSnapshot notifDoc,
    required Map<String, dynamic> data,
  }) async {
    // Tandai read
    if (data['isRead'] != true) {
      await notifDoc.reference.update({'isRead': true});
    }

    final String type = (data['type'] as String?)?.toLowerCase() ?? '';
    final String title = (data['title'] as String?) ?? '';
    final String? shopAppId = data['shopApplicationId'] as String?;
    final String? paymentAppId = data['paymentAppId'] as String?;

    // 1) Payment
    if (paymentAppId != null && paymentAppId.isNotEmpty) {
      PaymentRequestType requestType;
      if (type.startsWith('wallet_topup') || title.toLowerCase().contains('isi saldo')) {
        requestType = PaymentRequestType.topUp;
