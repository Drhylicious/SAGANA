import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../widgets/farmer_top_bar.dart';

class MyProgramsScreen extends StatefulWidget {
  const MyProgramsScreen({super.key});

  @override
  State<MyProgramsScreen> createState() => _MyProgramsScreenState();
}

class _MyProgramsScreenState extends State<MyProgramsScreen> {
  final _repo = FarmerProfileRepository();
  List<MyProgramEntry> _programs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final programs = await _repo.fetchMyPrograms();
    if (!mounted) return;
    setState(() {
      _programs = programs;
      _isLoading = false;
    });
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'withdrawn': return 'Withdrawn';
      case 'completed': return 'Completed';
      default: return 'Active';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                      : _programs.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text(
                                  'You are not enrolled in any programs yet.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                              itemCount: _programs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) => _ProgramCard(
                                entry: _programs[i],
                                formatDate: _formatDate,
                                statusLabel: _statusLabel,
                              ),
                            ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(
              title: 'My Programs',
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  final MyProgramEntry entry;
  final String Function(DateTime) formatDate;
  final String Function(String) statusLabel;

  const _ProgramCard({
    required this.entry,
    required this.formatDate,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF455A64).withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppConstants.programPurple.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.volunteer_activism_rounded,
                    color: AppConstants.programPurple, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(entry.programName,
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppConstants.programPurple.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(statusLabel(entry.enrollmentStatus),
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppConstants.programPurple)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!entry.isDistributed)
            Text('Awaiting distribution',
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant))
          else ...[
            Text(
              'Received ${entry.quantityGiven?.toStringAsFixed(1)}'
              '${entry.itemUnit != null ? ' ${entry.itemUnit}' : ''}'
              '${entry.itemName != null ? ' ${entry.itemName}' : ''} on ${formatDate(entry.distributedAt!)}',
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurface),
            ),
            if (entry.isRevenueShare) ...[
              const SizedBox(height: 6),
              if (entry.isSettled)
                Text(
                  'Returned ₱${entry.amountReturned?.toStringAsFixed(2)} on ${formatDate(entry.settledAt!)}',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
                      color: AppConstants.successGreen),
                )
              else
                Text(
                  entry.expectedReturnPercent != null
                      ? 'A ${entry.expectedReturnPercent}% return is due to the cooperative once sold.'
                      : 'A return is due to the cooperative once sold.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.warningAmber),
                ),
            ],
          ],
        ],
      ),
    );
  }
}