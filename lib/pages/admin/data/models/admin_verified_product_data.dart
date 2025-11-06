import 'package:cloud_firestore/cloud_firestore.dart';

class AdminVerifiedProductData {
  final String productId;
  final String name;
  final String imageUrl;
  final int price;
  final String category;
  final int stock;
  final int sold;
  final String storeName;
  final String storeId;
  final DateTime? createdAt;
  final Map<String, dynamic> rawData;

  AdminVerifiedProductData({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.category,
    required this.stock,
    required this.sold,
    required this.storeName,
    required this.storeId,
    this.createdAt,
    required this.rawData,
  });

  factory AdminVerifiedProductData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdminVerifiedProductData(
      productId: doc.id,
      name: data['name'] ?? '-',
      imageUrl: data['imageUrl'] ?? '',
      price: (data['price'] as num?)?.toInt() ?? 0,
      category: data['category'] ?? '-',
      stock: (data['stock'] as num?)?.toInt() ?? 0,
      sold: (data['sold'] as num?)?.toInt() ?? 0,
      storeName: data['storeName'] ?? '-',
      storeId: data['shopId'] ?? data['storeId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      rawData: data,
    );
  }
}
