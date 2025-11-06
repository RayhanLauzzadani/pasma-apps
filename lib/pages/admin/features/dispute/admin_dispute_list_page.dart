import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'admin_dispute_detail_page.dart';

class AdminDisputeListPage extends StatefulWidget {
  const AdminDisputeListPage({super.key});

  @override
  State<AdminDisputeListPage> createState() => _AdminDisputeListPageState();
}

class _AdminDisputeListPageState extends State<AdminDisputeListPage> {
  String _selectedFilter = 'open'; // open, all

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF373E3C)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Kelola Komplain',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF373E3C),
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter tabs
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                _buildFilterChip('Terbuka', 'open'),
                const SizedBox(width: 12),
                _buildFilterChip('Semua', 'all'),
              ],
            ),
          ),
          
          const SizedBox(height: 8),

          // Dispute list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getDisputeStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tidak ada komplain',
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final disputes = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: disputes.length,
                  itemBuilder: (context, index) {
                    final doc = disputes[index];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    return _buildDisputeCard(
                      disputeId: doc.id,
                      data: data,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1C55C0) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF1C55C0) : const Color(0xFFDDDDDD),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF777777),
          ),
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _getDisputeStream() {
    var query = FirebaseFirestore.instance
        .collection('orderDisputes')
        .orderBy('createdAt', descending: true);

    if (_selectedFilter == 'open') {
      query = query.where('status', isEqualTo: 'open');
    }

    return query.snapshots();
  }

  Widget _buildDisputeCard({
    required String disputeId,
    required Map<String, dynamic> data,
  }) {
    final invoiceId = data['invoiceId'] as String? ?? 'N/A';
    final reason = data['reason'] as String? ?? 'No reason';
    final status = data['status'] as String? ?? 'open';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminDisputeDetailPage(
              disputeId: disputeId,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                if (createdAt != null)
                  Text(
                    _formatTimeAgo(createdAt),
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: const Color(0xFF999999),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '#$invoiceId',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF373E3C),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Color(0xFFFF9800),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: const Color(0xFF666666),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tap untuk detail',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: const Color(0xFF1C55C0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF1C55C0),
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return const Color(0xFFFF9800);
      case 'investigating':
        return const Color(0xFF2196F3);
      case 'resolved':
        return const Color(0xFF28A745);
      case 'rejected':
        return const Color(0xFFFF3449);
      default:
        return const Color(0xFF999999);
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return 'Terbuka';
      case 'investigating':
        return 'Diproses';
      case 'resolved':
        return 'Selesai';
      case 'rejected':
        return 'Ditolak';
      default:
        return status;
    }
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }
}
