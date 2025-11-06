import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasma_apps/pages/admin/data/models/admin_store_data.dart';
import 'package:pasma_apps/pages/admin/features/approval/store/admin_store_approval_card.dart';
import 'package:pasma_apps/pages/admin/features/approval/store/admin_store_approval_detail_page.dart';
import 'package:pasma_apps/pages/buyer/features/store/store_detail_page.dart';
import 'package:lucide_icons/lucide_icons.dart';

// ===== TAB BAR WIDGET =====
class AdminStoreTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;

  const AdminStoreTabBar({
    super.key,
    required this.selectedIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = ["Pengajuan Toko", "Toko Terverifikasi"];
    final textStyle = GoogleFonts.dmSans(fontWeight: FontWeight.bold, fontSize: 15);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painters = List.generate(tabs.length, (i) {
          final tp = TextPainter(
            text: TextSpan(text: tabs[i], style: textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          return tp;
        });

        const spacing = 32.0;
        final lefts = <double>[];
        double left = 0;
        for (int i = 0; i < tabs.length; i++) {
          lefts.add(left);
          left += painters[i].width + spacing;
        }

        final underlineLeft = selectedIndex == 0 ? lefts[0] : lefts[1] - 4.0;
        final underlineWidth = painters[selectedIndex].width;

        return SizedBox(
          height: 40,
          child: Stack(
            alignment: Alignment.bottomLeft,
            children: [
              // Base line
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 2,
                  child: ColoredBox(color: Color(0x11B2B2B2)),
                ),
              ),
              // Tab labels
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(tabs.length, (i) {
                  final isActive = selectedIndex == i;
                  return GestureDetector(
                    onTap: isActive ? null : () => onTabChanged(i),
                    child: Container(
                      margin: EdgeInsets.only(right: i == 0 ? spacing : 0),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.ease,
                        style: GoogleFonts.dmSans(
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                          fontSize: 15,
                          color: isActive ? const Color(0xFF202020) : const Color(0xFFB2B2B2),
                        ),
                        child: Text(tabs[i]),
                      ),
                    ),
                  );
                }),
              ),
              // Yellow underline
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.ease,
                left: underlineLeft,
                bottom: 0,
                child: Container(
                  width: underlineWidth,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD600),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===== TAB 1: PENGAJUAN TOKO (PENDING) =====
class PendingStoreList extends StatelessWidget {
  final String searchQuery;

  const PendingStoreList({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('shopApplications')
            .where('status', isEqualTo: 'pending')
            .orderBy('submittedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Terjadi kesalahan: ${snapshot.error}'),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _emptyState("Belum ada pengajuan toko");
          }

          final allData = snapshot.data!.docs
              .map((doc) => AdminStoreApprovalData.fromDoc(doc))
              .toList();

          final filteredData = searchQuery.isEmpty
              ? allData
              : allData.where((data) {
                  final lowerQuery = searchQuery.toLowerCase();
                  return data.storeName.toLowerCase().contains(lowerQuery) ||
                      data.submitter.toLowerCase().contains(lowerQuery);
                }).toList();

          if (filteredData.isEmpty) {
            return _emptySearchResult();
          }

          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: filteredData.length,
            separatorBuilder: (context, index) => const SizedBox(height: 18),
            itemBuilder: (context, index) {
              final approvalData = filteredData[index];
              return AdminStoreApprovalCard(
                data: approvalData,
                isNetworkImage: true,
                onDetail: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdminStoreApprovalDetailPage(
                        docId: approvalData.docId,
                        approvalData: approvalData,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ===== TAB 2: TOKO TERVERIFIKASI (APPROVED) =====
class VerifiedStoreList extends StatelessWidget {
  final String searchQuery;

  const VerifiedStoreList({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('stores')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _emptyState("Belum ada toko terverifikasi");
        }

        var docs = snapshot.data!.docs;

        // Filter pencarian nama toko
        if (searchQuery.trim().isNotEmpty) {
          final q = searchQuery.trim().toLowerCase();
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final name = (data['name'] ?? '').toString().toLowerCase();
            return name.contains(q);
          }).toList();
        }

        if (docs.isEmpty) {
          return _emptySearchResult();
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final storeId = doc.id;

            return _VerifiedStoreCard(
              imageUrl: data['logoUrl'] ?? '',
              storeName: data['name'] ?? '',
              onTap: () async {
                // Cari shopApplications yang sudah approved untuk store ini
                final appQuery = await FirebaseFirestore.instance
                    .collection('shopApplications')
                    .where('status', isEqualTo: 'approved')
                    .get();

                // Cari doc yang cocok dengan storeId atau ownerId
                final ownerId = data['ownerId'] as String?;
                String? docId;
                for (final appDoc in appQuery.docs) {
                  final appData = appDoc.data();
                  // Cek apakah owner uid sama
                  if (appData['owner']?['uid'] == ownerId) {
                    docId = appDoc.id;
                    break;
                  }
                }

                if (docId != null && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminStoreApprovalDetailPage(
                        docId: docId!,
                        approvalData: null,
                      ),
                    ),
                  );
                } else {
                  // Fallback: buka StoreDetailPage jika tidak ketemu aplikasi
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StoreDetailPage(
                        store: {...data, 'id': storeId},
                      ),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}

// Custom Store Card tanpa rating untuk admin
class _VerifiedStoreCard extends StatelessWidget {
  final String imageUrl;
  final String storeName;
  final VoidCallback? onTap;

  const _VerifiedStoreCard({
    required this.imageUrl,
    required this.storeName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                imageUrl,
                width: 70,
                height: 70,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 70,
                  height: 70,
                  color: Colors.grey[200],
                  child: Icon(Icons.store, color: Colors.grey[400], size: 36),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    storeName,
                    style: const TextStyle(
                      color: Color(0xFF373E3C),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // Status badge Verified (hijau)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0x3329B057),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: const Color(0xFF29B057),
                ),
              ),
              child: Text(
                'Verified',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF29B057),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === HELPER WIDGETS ===
Widget _emptyState(String message) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.store, size: 54, color: const Color(0xFFE2E7EF)),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF9A9A9A),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _emptySearchResult() {
  return Center(
    child: Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.search, size: 48, color: const Color(0xFFE2E7EF)),
          const SizedBox(height: 12),
          Text(
            "Tidak ada hasil sesuai pencarian.",
            style: GoogleFonts.dmSans(fontSize: 16, color: const Color(0xFF9A9A9A)),
          ),
        ],
      ),
    ),
  );
}
