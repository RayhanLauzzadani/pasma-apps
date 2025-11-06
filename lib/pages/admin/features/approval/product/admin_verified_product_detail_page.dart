import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pasma_apps/pages/admin/data/models/admin_verified_product_data.dart';
import 'package:pasma_apps/data/models/category_type.dart';
import 'package:pasma_apps/pages/admin/widgets/success_dialog.dart';

class AdminVerifiedProductDetailPage extends StatelessWidget {
  final AdminVerifiedProductData product;

  const AdminVerifiedProductDetailPage({super.key, required this.product});

  String _formatPrice(int price) {
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(price);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('dd/MM/yyyy, HH:mm').format(date);
  }

  void _previewImage(BuildContext context, String url) {
    if (url.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image,
                size: 64,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _suspendProduct(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Suspend Produk?'),
        content: const Text(
          'Produk akan disembunyikan dari marketplace. Penjual akan menerima notifikasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Update status produk menjadi suspended
      await FirebaseFirestore.instance
          .collection('products')
          .doc(product.productId)
          .update({
        'status': 'suspended',
        'suspendedAt': FieldValue.serverTimestamp(),
      });

      // Kirim notifikasi ke seller
      final ownerId = product.rawData['ownerId'] ?? '';
      if (ownerId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('notifications')
            .add({
          'title': 'Produk Di-suspend',
          'body':
              'Produk "${product.name}" telah di-suspend oleh admin dan tidak tampil di marketplace.',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'type': 'product_suspended',
          'productId': product.productId,
        });
      }

      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              const SuccessDialog(message: "Produk Berhasil Di-suspend"),
        );
        await Future.delayed(const Duration(seconds: 2));
        Navigator.of(context, rootNavigator: true).pop();
        await Future.delayed(const Duration(milliseconds: 200));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal suspend produk: $e')),
        );
      }
    }
  }

  Future<void> _deleteProduct(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Produk?'),
        content: const Text(
          'Produk akan dihapus permanen dari sistem. Tindakan ini tidak dapat dibatalkan!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Hapus produk dari Firestore
      await FirebaseFirestore.instance
          .collection('products')
          .doc(product.productId)
          .delete();

      // Kirim notifikasi ke seller
      final ownerId = product.rawData['ownerId'] ?? '';
      if (ownerId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('notifications')
            .add({
          'title': 'Produk Dihapus',
          'body':
              'Produk "${product.name}" telah dihapus oleh admin karena melanggar kebijakan marketplace.',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'type': 'product_deleted',
          'productId': product.productId,
        });
      }

      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              const SuccessDialog(message: "Produk Berhasil Dihapus"),
        );
        await Future.delayed(const Duration(seconds: 2));
        Navigator.of(context, rootNavigator: true).pop();
        await Future.delayed(const Duration(milliseconds: 200));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus produk: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final varieties = product.rawData['varieties'] as List? ?? [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF373E3C)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Detail Produk Terverifikasi',
          style: GoogleFonts.dmSans(
            color: const Color(0xFF373E3C),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            GestureDetector(
              onTap: () => _previewImage(context, product.imageUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: product.imageUrl.isNotEmpty
                    ? Image.network(
                        product.imageUrl,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: double.infinity,
                          height: 200,
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image, size: 64),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        height: 200,
                        color: Colors.grey[200],
                        child: const Icon(Icons.shopping_bag, size: 64),
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // Product Name
            Text(
              product.name,
              style: GoogleFonts.dmSans(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF373E3C),
              ),
            ),
            const SizedBox(height: 12),

            // Category Badge
            Row(
              children: [
                CategoryBadge(type: mapCategoryType(product.category)),
              ],
            ),
            const SizedBox(height: 16),

            // Price & Stock
            _buildInfoRow('Harga', _formatPrice(product.price)),
            _buildInfoRow('Stok Tersedia', '${product.stock} unit'),
            _buildInfoRow('Total Terjual', '${product.sold} unit'),
            _buildInfoRow('Minimal Beli', '${product.rawData['minBuy'] ?? 1} unit'),
            _buildInfoRow('Nama Toko', product.storeName),
            _buildInfoRow('Tanggal Publikasi', _formatDate(product.createdAt)),

            const SizedBox(height: 16),

            // Description
            Text(
              'Deskripsi',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF373E3C),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.rawData['description'] ?? '-',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: const Color(0xFF6B7280),
                height: 1.5,
              ),
            ),

            // Varieties
            if (varieties.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Varian Produk',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF373E3C),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: varieties.map((v) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      v.toString(),
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: const Color(0xFF373E3C),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _suspendProduct(context),
                    child: Text(
                      'Suspend',
                      style: GoogleFonts.dmSans(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _deleteProduct(context),
                    child: Text(
                      'Hapus',
                      style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
}
