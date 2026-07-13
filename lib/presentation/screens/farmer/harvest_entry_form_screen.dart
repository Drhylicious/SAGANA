import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/repositories/harvest_entry_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

class HarvestEntryFormScreen extends StatefulWidget {
  final dynamic crop;
  const HarvestEntryFormScreen({super.key, this.crop});

  @override
  State<HarvestEntryFormScreen> createState() =>
      _HarvestEntryFormScreenState();
}

class _HarvestEntryFormScreenState extends State<HarvestEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _varietyController = TextEditingController();
  final _storageController = TextEditingController();
  final _notesController = TextEditingController();
  final _repo = HarvestEntryRepository();

  late FarmerCropModel _crop;
  late String _batchNumber;

  String _selectedGrade = 'Grade A';
  DateTime _harvestDate = DateTime.now();
  bool _isLoading = false;
  bool _isSuccess = false;
  String? _errorMessage;
  bool _isOnline = true;
  bool _cropLoaded = false;
  bool _cropMissing = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_cropLoaded) {
      // Prefer explicit route extra passed by GoRouter, fall back to
      // ModalRoute arguments for legacy callers.
      final arg = widget.crop ?? ModalRoute.of(context)?.settings.arguments;
      if (arg is FarmerCropModel) {
        _crop = arg;
        final code = _crop.cropName.length >= 4
            ? _crop.cropName.substring(0, 4).toUpperCase()
            : _crop.cropName.toUpperCase();
        _batchNumber = AppUtils.generateBatchNumber(code);
        _cropLoaded = true;
      } else {
        _cropMissing = true;
        _cropLoaded = true;
      }
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _varietyController.dispose();
    _storageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _harvestDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppConstants.primaryGreen,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _harvestDate = picked);
  }

  Future<void> _handleSubmit() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    final qty = double.tryParse(_quantityController.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _errorMessage = 'Please enter a valid quantity.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final cropLower = _crop.cropName.toLowerCase();
      final isCoop = cropLower.contains('palay') ||
          cropLower.contains('peanut') ||
          cropLower.contains('mani');

      await _repo.submitHarvest(
        cropId: _crop.id,
        cropName: _crop.cropName,
        cropCategory: _crop.category,
        quantityKg: qty,
        qualityGrade: _selectedGrade,
        harvestDate: _harvestDate,
        batchNumber: _batchNumber,
        variety: _varietyController.text.trim().isEmpty
            ? null
            : _varietyController.text.trim(),
        storageLocation: _storageController.text.trim().isEmpty
            ? null
            : _storageController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        submittedToCooperative: isCoop,
      );

      AppEventService.instance.notifyHarvestRecorded();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) _showSuccessDialog(qty, isCoop);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Failed to submit harvest. Please check your connection and try again.';
      });
    }
  }

  void _showSuccessDialog(double qty, bool isCoop) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppConstants.successGreen.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppConstants.successGreen, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Harvest Submitted!',
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppConstants.charcoal)),
            const SizedBox(height: 8),
            Text(
              '${qty.toStringAsFixed(0)} kg of ${_crop.cropName} recorded '
              '(Batch #$_batchNumber).'
              '${isCoop ? '\n\nMarked as submitted to the SP3 Cooperative.' : ''}',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Done',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_cropLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(
            color: AppConstants.primaryGreen)),
      );
    }

    if (_cropMissing) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 56, color: AppConstants.errorRed),
                const SizedBox(height: 12),
                Text('Crop not found', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('No crop data was provided. Please return to the crop listing and try again.', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 72),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 160),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Crop header
                        _CropHeaderCard(crop: _crop),
                        const SizedBox(height: 16),

                        // ── Quantity ──────────────────────────────────────
                        _QuantityField(controller: _quantityController),
                        const SizedBox(height: 20),

                        // ── Quality Grade ─────────────────────────────────
                        const _FieldLabel('Quality Grade*'),
                        const SizedBox(height: 8),
                        _GradeSelector(
                          selected: _selectedGrade,
                          onChanged: (g) => setState(() => _selectedGrade = g),
                        ),
                        const SizedBox(height: 20),

                        // ── Variety ───────────────────────────────────────
                        const _FieldLabel('Variety (Optional)'),
                        const SizedBox(height: 8),
                        _SimpleTextField(
                          controller: _varietyController,
                          hint: 'e.g. IR64, Sinandomeng',
                          icon: Icons.spa_outlined,
                        ),
                        const SizedBox(height: 16),

                        // ── Batch Number ──────────────────────────────────
                        const _FieldLabel('Batch Number'),
                        const SizedBox(height: 8),
                        _BatchNumberField(batchNumber: _batchNumber),
                        const SizedBox(height: 16),

                        // ── Harvest Date ──────────────────────────────────
                        const _FieldLabel('Harvest Date'),
                        const SizedBox(height: 8),
                        _DateField(date: _harvestDate, onTap: _pickDate),
                        const SizedBox(height: 16),

                        // ── Storage Location ──────────────────────────────
                        const _FieldLabel('Storage Location'),
                        const SizedBox(height: 8),
                        _SimpleTextField(
                          controller: _storageController,
                          hint: 'e.g. Bodega 1, Home Storage',
                          icon: Icons.location_on_outlined,
                        ),
                        const SizedBox(height: 16),

                        // ── Notes ─────────────────────────────────────────
                        const _FieldLabel('Notes'),
                        const SizedBox(height: 8),
                        _NotesField(controller: _notesController),
                        const SizedBox(height: 16),

                        // ── Error ─────────────────────────────────────────
                        if (_errorMessage != null) _ErrorBanner(message: _errorMessage!),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ───────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(
              title: _crop.cropName,
              onBack: () => Navigator.of(context).pop(),
              profilePhotoUrl: null,
              onProfileTap: () {},
              onNotificationTap: () => context.pushRoute(AppRoutes.farmerNotifications),
              onSettingsTap: null,
              trailing: [
                _OnlineBadge(isOnline: _isOnline),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => context.pushRoute(AppRoutes.farmerNotifications),
                  child: const Icon(Icons.notifications_outlined, color: AppConstants.primaryGreen, size: 26),
                ),
              ],
            ),
          ),

          // ── Submit Button ─────────────────────────────────────────────
          Positioned(
            bottom: 72, left: 0, right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: _SubmitButton(
                isLoading: _isLoading,
                isSuccess: _isSuccess,
                onPressed: _handleSubmit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _OnlineBadge extends StatelessWidget {
  final bool isOnline;
  const _OnlineBadge({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppConstants.successGreen : AppConstants.warningAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: color),
          const SizedBox(width: 5),
          Text(isOnline ? 'Online' : 'Offline',
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 7, height: 7,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop Header Card
// ─────────────────────────────────────────────────────────────────────────────

class _CropHeaderCard extends StatelessWidget {
  final FarmerCropModel crop;
  const _CropHeaderCard({required this.crop});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 20, offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Crop photo or icon
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: crop.hasPhoto
                    ? Image.network(
                        crop.photoUrl!,
                        width: 64, height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _CropIconBox(category: crop.category),
                      )
                    : _CropIconBox(category: crop.category),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CROP NAME',
                        style: GoogleFonts.poppins(
                            fontSize: 9, fontWeight: FontWeight.w500,
                            color: AppConstants.onSurfaceVariant,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 2),
                    Text(crop.cropName,
                        style: GoogleFonts.poppins(
                            fontSize: 18, fontWeight: FontWeight.w700,
                            color: AppConstants.primaryGreen)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.secondaryContainer.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(color: AppConstants.amber.withValues(alpha: 0.20)),
                ),
                child: Text(crop.category,
                    style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w500,
                        color: AppConstants.amber)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropIconBox extends StatelessWidget {
  final String category;
  const _CropIconBox({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64, height: 64,
      decoration: BoxDecoration(
        color: AppConstants.onPrimaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_cropIcon(category), color: AppConstants.primaryGreen, size: 32),
    );
  }

  IconData _cropIcon(String category) {
    switch (category) {
      case 'Grain': return Icons.grass_rounded;
      case 'Legume': return Icons.eco_rounded;
      case 'Root & Spice Crop': return Icons.spa_rounded;
      case 'Fruit': return Icons.local_florist_rounded;
      case 'Tree Crop': return Icons.park_rounded;
      case 'Vegetable': return Icons.agriculture_rounded;
      default: return Icons.eco_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quantity Field
// ─────────────────────────────────────────────────────────────────────────────

class _QuantityField extends StatelessWidget {
  final TextEditingController controller;
  const _QuantityField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Quantity (kg)*'),
        const SizedBox(height: 8),
        Stack(
          alignment: Alignment.centerRight,
          children: [
            TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: GoogleFonts.poppins(
                  fontSize: 36, fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: GoogleFonts.poppins(
                    fontSize: 36, fontWeight: FontWeight.w700,
                    color: AppConstants.outline.withValues(alpha: 0.30)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 20, horizontal: 48),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  borderSide: BorderSide(
                      color: AppConstants.outline.withValues(alpha: 0.20), width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  borderSide: BorderSide(
                      color: AppConstants.outline.withValues(alpha: 0.20), width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  borderSide: const BorderSide(
                      color: AppConstants.primaryContainer, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  borderSide: const BorderSide(
                      color: AppConstants.errorRed, width: 2),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Quantity is required';
                final qty = double.tryParse(v);
                if (qty == null || qty <= 0) return 'Enter a valid quantity';
                return null;
              },
            ),
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Text('KG',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: AppConstants.outline)),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grade Selector
// ─────────────────────────────────────────────────────────────────────────────

class _GradeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _GradeSelector({required this.selected, required this.onChanged});

  static const _grades = ['Grade A', 'Grade B', 'Grade C'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFDBF1FE),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: _grades.map((grade) {
          final isActive = grade == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(grade),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isActive ? AppConstants.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Text(grade,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w500,
                        color: isActive
                            ? AppConstants.onPrimaryContainer
                            : AppConstants.onSurfaceVariant)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch Number Field
// ─────────────────────────────────────────────────────────────────────────────

class _BatchNumberField extends StatelessWidget {
  final String batchNumber;
  const _BatchNumberField({required this.batchNumber});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        TextFormField(
          initialValue: batchNumber,
          readOnly: true,
          style: GoogleFonts.inter(
              fontSize: 13, color: AppConstants.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()]),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFE6F6FF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.20)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.20)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.20)),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(right: 14),
          child: Icon(Icons.lock_outline_rounded,
              size: 18, color: AppConstants.outline),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date Field
// ─────────────────────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _DateField({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
              color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(DateFormat('MMMM d, yyyy').format(date),
                  style: GoogleFonts.inter(
                      fontSize: 14, color: AppConstants.onSurface)),
            ),
            const Icon(Icons.calendar_today_rounded,
                size: 18, color: AppConstants.primaryGreen),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple Text Field
// ─────────────────────────────────────────────────────────────────────────────

class _SimpleTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;

  const _SimpleTextField({
    required this.controller,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: AppConstants.outline.withValues(alpha: 0.50)),
        suffixIcon: Icon(icon, size: 20, color: AppConstants.primaryGreen),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(
              color: AppConstants.primaryContainer, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notes Field
// ─────────────────────────────────────────────────────────────────────────────

class _NotesField extends StatelessWidget {
  final TextEditingController controller;
  const _NotesField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: 3,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: 'Describe crop conditions, humidity, weather, etc.',
        hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: AppConstants.outline.withValues(alpha: 0.50)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(
              color: AppConstants.primaryContainer, width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Field Label
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w500,
              color: AppConstants.onSurfaceVariant)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error Banner
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
            color: AppConstants.errorRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppConstants.errorRed),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.errorRed))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Submit Button
// ─────────────────────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool isLoading;
  final bool isSuccess;
  final VoidCallback onPressed;

  const _SubmitButton({
    required this.isLoading,
    required this.isSuccess,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: isSuccess
                ? [AppConstants.successGreen, AppConstants.successGreen]
                : [AppConstants.primaryGreen, AppConstants.primaryContainer],
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          boxShadow: [
            BoxShadow(
              color: AppConstants.primaryGreen.withValues(alpha: 0.30),
              blurRadius: 24, offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: (isLoading || isSuccess) ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
              : Text(
                  isSuccess ? 'Submitted!' : 'Submit Harvest',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w500,
                      color: Colors.white)),
        ),
      ),
    );
  }
}

