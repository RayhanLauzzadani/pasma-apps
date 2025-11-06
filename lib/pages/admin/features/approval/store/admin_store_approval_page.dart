import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasma_apps/pages/admin/data/models/admin_store_data.dart';
import 'package:pasma_apps/pages/admin/widgets/admin_search_bar.dart';
import 'package:pasma_apps/pages/admin/features/approval/store/admin_store_approval_card.dart';
import 'package:pasma_apps/pages/admin/features/approval/store/admin_store_approval_detail_page.dart';
import 'package:pasma_apps/pages/buyer/features/store/store_card.dart';
import 'package:pasma_apps/pages/buyer/features/store/store_detail_page.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pasma_apps/pages/admin/features/approval/store/_admin_store_widgets.dart';

class AdminStoreApprovalPage extends StatefulWidget {
  final int initialTabIndex;
  const AdminStoreApprovalPage({super.key, this.initialTabIndex = 0});

  @override
  State<AdminStoreApprovalPage> createState() => _AdminStoreApprovalPageState();
}

class _AdminStoreApprovalPageState extends State<AdminStoreApprovalPage>
    with SingleTickerProviderStateMixin {
  String _searchQuery = "";
  int _tabIndex = 0;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTabIndex.clamp(0, 1);
    _tabController = TabController(length: 2, vsync: this, initialIndex: _tabIndex);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 31),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Persetujuan Toko',
                style: GoogleFonts.dmSans(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF373E3C),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tab Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AdminStoreTabBar(
                selectedIndex: _tabIndex,
                onTabChanged: (idx) {
                  setState(() {
                    _tabIndex = idx;
                    _tabController.animateTo(idx);
                  });
                },
              ),
            ),
            const SizedBox(height: 16),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AdminSearchBar(
                hintText: _tabIndex == 0
                    ? "Cari Nama Toko / Pemilik"
                    : "Cari Toko Terverifikasi",
                onChanged: (q) => setState(() => _searchQuery = q),
              ),
            ),
            const SizedBox(height: 16),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Tab 0: Pengajuan Toko (Pending)
                  PendingStoreList(searchQuery: _searchQuery),

                  // Tab 1: Toko Terverifikasi (Approved)
                  VerifiedStoreList(searchQuery: _searchQuery),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _emptyStoreSubmissions() {
  return Center(
    child: Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.store,     // icon lucide
            size: 54,
            color: const Color(0xFFE2E7EF),
          ),
          const SizedBox(height: 16),
          Text(
            "Belum ada pengajuan toko",
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: const Color(0xFF373E3C),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            "Semua pengajuan toko akan tampil di sini\njika ada toko baru dari penjual.",
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: const Color(0xFF9A9A9A),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
