import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'product_approval_card.dart';
import 'package:pasma_apps/data/models/category_type.dart';
import 'package:pasma_apps/pages/admin/data/models/admin_product_data.dart';
import 'package:pasma_apps/pages/admin/data/models/admin_verified_product_data.dart';
import 'package:pasma_apps/pages/admin/features/approval/product/admin_product_approval_detail_page.dart';
import 'package:pasma_apps/pages/admin/features/approval/product/admin_verified_product_detail_page.dart';
import 'package:pasma_apps/pages/admin/widgets/admin_search_bar.dart';
import 'package:pasma_apps/pages/admin/widgets/admin_verified_product_card.dart';
import 'package:pasma_apps/pages/admin/widgets/admin_product_tab_bar.dart';
import 'package:pasma_apps/widgets/category_selector.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class AdminProductApprovalPage extends StatefulWidget {
  final int initialTabIndex;
  const AdminProductApprovalPage({super.key, this.initialTabIndex = 0});

  @override
  State<AdminProductApprovalPage> createState() =>
      _AdminProductApprovalPageState();
}

class _AdminProductApprovalPageState extends State<AdminProductApprovalPage>
    with SingleTickerProviderStateMixin {
  final List<CategoryType> categories = [
    CategoryType.merchandise,
    CategoryType.alatTulis,
    CategoryType.alatLab,
    CategoryType.produkDaurUlang,
    CategoryType.produkKesehatan,
    CategoryType.makanan,
    CategoryType.minuman,
    CategoryType.snacks,
    CategoryType.lainnya,
  ];

  int _selectedCategory = 0; // 0 = Semua
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  int _tabIndex = 0;

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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 31),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              "Persetujuan Produk",
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold,
                fontSize: 24,
                color: const Color(0xFF373E3C),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // TabBar - Custom yellow underline style
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AdminProductTabBar(
              selectedIndex: _tabIndex,
              onTabChanged: (idx) {
                setState(() {
                  _tabIndex = idx;
                  _tabController.animateTo(idx);
                });
              },
            ),
          ),
          const SizedBox(height: 23),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AdminSearchBar(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchText = val),
            ),
          ),
          const SizedBox(height: 16),

          // KATEGORI
          CategorySelector(
            categories: categories,
            selectedIndex: _selectedCategory,
            onSelected: (i) => setState(() => _selectedCategory = i),
            padding: const EdgeInsets.only(left: 20, right: 8),
          ),
          const SizedBox(height: 21),

          // TabBarView
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildPendingTab(),
                _buildVerifiedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Tab Menunggu Persetujuan
  Widget _buildPendingTab() {
    return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('productsApplication')
                  .where('status', isEqualTo: 'Menunggu')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Terjadi error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                final products = docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final categoryLabel = (data['category'] ?? '').toString();
                  final categoryType = categories.firstWhere(
                    (cat) => categoryLabels[cat] == categoryLabel,
                    orElse: () => CategoryType.lainnya,
                  );

                  String date = "-";
                  final createdAt = data['createdAt'];
                  if (createdAt != null) {
                    final dt = createdAt is Timestamp
                        ? createdAt.toDate()
                        : DateTime.tryParse(createdAt.toString());
                    if (dt != null) {
                      date =
                          "${dt.day.toString().padLeft(2,'0')}/"
                          "${dt.month.toString().padLeft(2,'0')}/"
                          "${dt.year}, "
                          "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
                    }
                  }

                  return AdminProductData(
                    docId: doc.id,
                    imagePath: data['imageUrl'] ?? '',
                    productName: data['name'] ?? '-',
                    categoryType: categoryType,
                    storeName: data['storeName'] ?? '',
                    date: date,
                    status: data['status'] ?? 'Menunggu',
                    description: data['description'] ?? '-',
                    price: (data['price'] is int)
                        ? data['price']
                        : int.tryParse('${data['price'] ?? 0}') ?? 0,
                    stock: (data['stock'] is int)
                        ? data['stock']
                        : int.tryParse('${data['stock'] ?? 0}') ?? 0,
                    shopId: data['shopId'] ?? '',
                    ownerId: data['ownerId'] ?? '',
                    rawData: data,
                  );
                }).toList();

                final filteredProducts = products.where((p) {
                  final matchCategory = _selectedCategory == 0
                      ? true
                      : p.categoryType == categories[_selectedCategory - 1];
                  final matchSearch = _searchText.isEmpty
                      ? true
                      : p.productName.toLowerCase().contains(_searchText.toLowerCase()) ||
                        p.storeName.toLowerCase().contains(_searchText.toLowerCase());
                  return matchCategory && matchSearch;
                }).toList();

                if (filteredProducts.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 64),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_rounded, size: 54, color: const Color(0xFFE2E7EF)),
                          const SizedBox(height: 16),
                          Text(
                            "Belum ada pengajuan produk",
                            style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: const Color(0xFF373E3C),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Semua pengajuan produk akan tampil di sini\njika ada produk baru dari penjual.",
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

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: filteredProducts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 20),
                  itemBuilder: (context, idx) {
                    final p = filteredProducts[idx];
                    return ProductApprovalCard(
                      data: p,
                      onDetail: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminProductApprovalDetailPage(data: p),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
  }

  // Tab Produk Terverifikasi
  Widget _buildVerifiedTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Terjadi error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final products = docs.map((doc) {
          return AdminVerifiedProductData.fromFirestore(doc);
        }).toList();

        // Filter berdasarkan kategori dan search
        final filteredProducts = products.where((p) {
          final matchCategory = _selectedCategory == 0
              ? true
              : p.category == categoryLabels[categories[_selectedCategory - 1]];
          final matchSearch = _searchText.isEmpty
              ? true
              : p.name.toLowerCase().contains(_searchText.toLowerCase()) ||
                p.storeName.toLowerCase().contains(_searchText.toLowerCase());
          return matchCategory && matchSearch;
        }).toList();

        if (filteredProducts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 64),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 54, color: const Color(0xFFE2E7EF)),
                  const SizedBox(height: 16),
                  Text(
                    "Belum ada produk terverifikasi",
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: const Color(0xFF373E3C),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Produk yang telah disetujui\nakan tampil di sini.",
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

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          itemCount: filteredProducts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, idx) {
            final p = filteredProducts[idx];
            return AdminVerifiedProductCard(
              product: p,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminVerifiedProductDetailPage(product: p),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
