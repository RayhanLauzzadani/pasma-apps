import 'package:abc_e_mart/buyer/widgets/logout_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:abc_e_mart/admin/widgets/admin_home_header.dart';
import 'package:abc_e_mart/admin/widgets/admin_summary_card.dart';
import 'package:abc_e_mart/admin/widgets/admin_abc_payment_section.dart';
import 'package:abc_e_mart/admin/widgets/admin_store_submission_section.dart';
import 'package:abc_e_mart/admin/widgets/admin_product_submission_section.dart';
import 'package:abc_e_mart/admin/widgets/admin_bottom_navbar.dart';
import 'package:abc_e_mart/admin/features/approval/store/admin_store_approval_page.dart';
import 'package:abc_e_mart/admin/features/approval/product/admin_product_approval_page.dart';
import 'package:abc_e_mart/admin/widgets/admin_ad_submission_section.dart';
import 'package:abc_e_mart/admin/features/approval/ad/admin_ad_approval_page.dart';
import 'package:abc_e_mart/admin/features/approval/ad/admin_ad_approval_detail_page.dart';
import 'package:abc_e_mart/buyer/features/auth/login_page.dart';
import 'package:abc_e_mart/admin/features/approval/payment/admin_payment_approval_page.dart';
import 'package:abc_e_mart/admin/features/approval/store/admin_store_approval_detail_page.dart';
import 'package:abc_e_mart/admin/features/notification/notification_page_admin.dart';
import 'package:abc_e_mart/admin/features/approval/payment/admin_payment_approval_detail_page.dart';
import 'package:abc_e_mart/data/models/category_type.dart';
import 'package:abc_e_mart/seller/data/models/ad.dart';
import 'package:intl/intl.dart';

// ADD: detach token saat logout/force-logout
import 'package:abc_e_mart/data/services/fcm_token_registrar.dart';

class HomePageAdmin extends StatefulWidget {
  const HomePageAdmin({super.key});

  @override
  State<HomePageAdmin> createState() => _HomePageAdminState();
}

class _HomePageAdminState extends State<HomePageAdmin> {
  int _currentIndex = 0;
  bool _isExiting = false;

  // Guard agar tidak double-logout
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _checkAdminClaim();
  }

  Future<void> _checkAdminClaim() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _forceLogoutWithMsg('Anda belum login.');
      return;
    }
    try {
      final token = await user.getIdTokenResult(true);
      final claims = token.claims;
      if (claims == null || claims['admin'] != true) {
        _forceLogoutWithMsg('Akses admin diperlukan. Silakan login dengan akun admin.');
      }
    } catch (e) {
      _forceLogoutWithMsg('Terjadi error: $e');
    }
  }

  void _forceLogoutWithMsg(String message) async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    // DETACH token lebih dulu agar tidak “nempel” di akun lama
    try {
      await FcmTokenRegistrar.unregister();
    } catch (_) {
      // swallow error agar UI tetap jalan
    }

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // swallow error agar UI tetap jalan
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Akses Ditolak'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    _isLoggingOut = false;
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;

    final result = await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const LogoutConfirmationDialog(),
    );

    if (result == true) {
      _isLoggingOut = true;

      // DETACH token sebelum signOut
      try {
        await FcmTokenRegistrar.unregister();
      } catch (_) {
        // swallow error
      }

      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {
        // swallow error
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );

      _isLoggingOut = false;
    }
  }

  Future<List<AdminAbcPaymentData>> _mapPaymentAppsToUi(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    return Future.wait(docs.map((d) async {
      final m = d.data();
      final typeStr = (m['type'] as String? ?? '').toLowerCase();
      final isWithdraw = typeStr == 'withdrawal';
      final submittedAt = (m['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now();

      if (isWithdraw) {
        // Tampilkan nama toko
        String name = 'Penjual';
        final storeId = m['storeId'] as String?;
        if (storeId != null && storeId.isNotEmpty) {
          final st =
              await FirebaseFirestore.instance.collection('stores').doc(storeId).get();
          name = (st.data()?['name'] as String?) ?? name;
        }
        final amount = (m['amount'] as num?)?.toInt() ?? 0; // nominal diajukan
        return AdminAbcPaymentData(
          applicationId: d.id,
          name: name,
          isSeller: true,
          type: AbcPaymentType.withdraw,
          amount: amount,
          createdAt: submittedAt,
        );
      } else {
        // Top-up → tampilkan nama user (fallback email)
        String name = (m['buyerEmail'] as String?) ?? 'Pembeli';
        final buyerId = m['buyerId'] as String?;
        if (buyerId != null && buyerId.isNotEmpty) {
          final u =
              await FirebaseFirestore.instance.collection('users').doc(buyerId).get();
          name = (u.data()?['displayName'] as String?) ??
              (u.data()?['name'] as String?) ??
              name;
        }
        final amount = (m['amount'] as num?)?.toInt() ?? 0; // jumlah isi saldo
        return AdminAbcPaymentData(
          applicationId: d.id,
          name: name,
          isSeller: false,
          type: AbcPaymentType.topup,
          amount: amount,
          createdAt: submittedAt,
        );
      }
    }));
  }

  String _formatDate(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/"
        "${dt.month.toString().padLeft(2, '0')}/"
        "${dt.year}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    Widget mainBody;

    if (_currentIndex == 1) {
      mainBody = const AdminPaymentApprovalPage();
    } else if (_currentIndex == 2) {
      mainBody = const AdminStoreApprovalPage();
    } else if (_currentIndex == 3) {
      mainBody = const AdminProductApprovalPage();
    } else if (_currentIndex == 4) {
      mainBody = const AdminAdApprovalPage();
    } else {
      mainBody = Column(
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 16,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: const Color.fromRGBO(0, 0, 0, 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: AdminHomeHeader(
              onNotif: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationPageAdmin(),
                  ),
                );
              },
              onLogoutTap: _logout,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Admin Summary Card ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('shopApplications')
                          .snapshots(),
                      builder: (context, shopSnapshot) {
                        int tokoBaru = 0;
                        int tokoTerdaftar = 0;
                        if (shopSnapshot.hasData) {
                          final docs = shopSnapshot.data!.docs;
                          tokoBaru = docs
                              .where((doc) =>
                                  (doc['status'] ?? '').toString().toLowerCase() == 'pending')
                              .length;
                          tokoTerdaftar = docs
                              .where((doc) =>
                                  (doc['status'] ?? '').toString().toLowerCase() == 'approved')
                              .length;
                        }
                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('productsApplication')
                              .snapshots(),
                          builder: (context, prodSnapshot) {
                            int produkBaru = 0;
                            int produkDisetujui = 0;
                            if (prodSnapshot.hasData) {
                              final prods = prodSnapshot.data!.docs;
                              produkBaru = prods.where((doc) {
                                final status =
                                    (doc['status'] ?? '').toString().toLowerCase();
                                return status == 'menunggu' || status == 'pending';
                              }).length;
                              produkDisetujui = prods.where((doc) {
                                final status =
                                    (doc['status'] ?? '').toString().toLowerCase();
                                return status == 'sukses' || status == 'approved';
                              }).length;
                            }
                            // --- QUERY IKLAN BARU & DISETUJUI (Real) ---
                            return StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('adsApplication')
                                  .snapshots(),
                              builder: (context, adSnap) {
                                int iklanBaru = 0;
                                int iklanDisetujui = 0;
                                if (adSnap.hasData) {
                                  final ads = adSnap.data!.docs;
                                  iklanBaru = ads
                                      .where((doc) =>
