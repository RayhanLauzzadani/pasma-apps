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
