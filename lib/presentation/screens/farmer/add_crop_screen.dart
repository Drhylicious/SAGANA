import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

class AddCropScreen extends StatefulWidget {
  const AddCropScreen({super.key});

  @override
  State<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends State<AddCropScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _cropNameController = TextEditingController();
  final _cropRepo = CropRepository();
  final _picker = ImagePicker();

  String? _selectedCategory;
  XFile? _cropImage;
  bool _isLoading = false;
  bool _isSuccess = false;
  String? _errorMessage;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 6, end: -6), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    _cropNameController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  static const List<Map<String, String>> _categories = [
    {
      'value': 'Grain',
      'label': 'Grain',
      'example': 'e.g. Palay, Rice, Corn, Wheat',
    },
    {
      'value': 'Legume',
      'label': 'Legume',
      'example': 'e.g. Peanut, Mung Bean, Soybean',
    },
    {
      'value': 'Root & Spice Crop',
      'label': 'Root & Spice Crop',
      'example': 'e.g. Ginger, Garlic, Kamote, Cassava',
    },
    {
      'value': 'Fruit',
      'label': 'Fruit',
      'example': 'e.g. Banana, Mango, Papaya',
    },
    {
      'value': 'Tree Crop',
      'label': 'Tree Crop',
      'example': 'e.g. Copra, Coconut',
    },
    {
      'value': 'Vegetable',
      'label': 'Vegetable',
      'example': 'e.g. Pechay, Sitaw, Kangkong',
    },
    {
      'value': 'Other',
      'label': 'Other',
      'example': 'Any crop not listed above',
    },
  ];

  // ── Pick crop image ───────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null && mounted) {
      setState(() => _cropImage = picked);
    }
  }

  void _removeImage() => setState(() => _cropImage = null);

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _handleCreate() async {
    setState(() => _errorMessage = null);

    final isValid = _formKey.currentState!.validate();
    if (!isValid || _selectedCategory == null) {
      _shakeController.forward(from: 0);
      if (_selectedCategory == null) {
        setState(() => _errorMessage = 'Please select a category.');
      }
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      // Upload image if selected
      String? photoUrl;
      if (_cropImage != null) {
        final Uint8List bytes = await _cropImage!.readAsBytes();
        final ext = _cropImage!.name.split('.').last;
        photoUrl = await _cropRepo.uploadCropImage(
          cropName: _cropNameController.text.trim(),
          imageBytes: bytes,
          fileExtension: ext,
        );
      }

      await _cropRepo.addCrop(
        cropName: _cropNameController.text.trim(),
        category: _selectedCategory!,
        photoUrl: photoUrl,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      setState(() {
        _isLoading = false;
        _errorMessage = msg.contains('unique') || msg.contains('duplicate')
            ? '"${_cropNameController.text.trim()}" is already in your crop list.'
            : 'Failed to add crop. Please try again.';
      });
      _shakeController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Crop Image Picker ──────────────────────────────
                      _CropImagePicker(
                        image: _cropImage,
                        onPick: _pickImage,
                        onRemove: _removeImage,
                      ),
                      const SizedBox(height: 24),

                      // ── Form ───────────────────────────────────────────
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FieldLabel('Crop Name'),
                            const SizedBox(height: 8),
                            _CropNameField(controller: _cropNameController),
                            const SizedBox(height: 20),
                            _FieldLabel('Category'),
                            const SizedBox(height: 8),
                            _CategoryDropdown(
                              categories: _categories,
                              selectedValue: _selectedCategory,
                              onChanged: (val) => setState(() {
                                _selectedCategory = val;
                                _errorMessage = null;
                              }),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                'Select the category that best describes this crop',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppConstants.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      if (_errorMessage != null)
                        _ErrorBanner(message: _errorMessage!),

                      const SizedBox(height: 20),

                      _SmartSuggestionCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: 'Add New Crop',
              onBack: () => Navigator.of(context).pop(false),
              profilePhotoUrl: null,
              onProfileTap: () {},
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
              onSettingsTap: null,
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomActionBar(
              shakeAnimation: _shakeAnimation,
              shakeController: _shakeController,
              isLoading: _isLoading,
              isSuccess: _isSuccess,
              onPressed: _handleCreate,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop Image Picker
// ─────────────────────────────────────────────────────────────────────────────

class _CropImagePicker extends StatelessWidget {
  final XFile? image;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _CropImagePicker({
    required this.image,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Crop Photo (Optional)',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppConstants.charcoal,
            ),
          ),
        ),
        GestureDetector(
          onTap: image == null ? onPick : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: image != null
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  border: Border.all(
                    color: image != null
                        ? Colors.transparent
                        : AppConstants.outline.withValues(alpha: 0.20),
                    width: image != null ? 0 : 2,
                    style: image != null ? BorderStyle.none : BorderStyle.solid,
                  ),
                ),
                child: image != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            image!.path,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _PlaceholderContent(hasImage: false),
                          ),
                          // Remove button overlay
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: onRemove,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.60),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          // Change photo button overlay
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: onPick,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.60),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.edit_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Change',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : _PlaceholderContent(hasImage: false),
              ),
            ),
          ),
        ),
        if (image == null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              'Tap to add a photo of your crop — helps with easy identification',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppConstants.outline,
              ),
            ),
          ),
      ],
    );
  }
}

class _PlaceholderContent extends StatelessWidget {
  final bool hasImage;
  const _PlaceholderContent({required this.hasImage});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppConstants.primaryGreen.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.add_photo_alternate_outlined,
            size: 28,
            color: AppConstants.primaryGreen.withValues(alpha: 0.60),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Add Crop Photo',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppConstants.primaryGreen.withValues(alpha: 0.70),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Optional — tap to upload from gallery',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppConstants.outline.withValues(alpha: 0.60),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form Fields
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppConstants.charcoal,
        ),
      ),
    );
  }
}

class _CropNameField extends StatelessWidget {
  final TextEditingController controller;
  const _CropNameField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.text,
      textCapitalization: TextCapitalization.words,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: 'e.g., Rice, Kamote',
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppConstants.outline.withValues(alpha: 0.50),
        ),
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(
          Icons.eco_outlined,
          size: 20,
          color: AppConstants.outline,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(
            color: AppConstants.primaryContainer,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(color: AppConstants.errorRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(color: AppConstants.errorRed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Crop name is required';
        if (v.trim().length < 2) return 'Enter a valid crop name';
        return null;
      },
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final List<Map<String, String>> categories;
  final String? selectedValue;
  final ValueChanged<String?> onChanged;

  const _CategoryDropdown({
    required this.categories,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: selectedValue,
      onChanged: onChanged,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      icon: const Icon(
        Icons.expand_more_rounded,
        color: AppConstants.outline,
        size: 20,
      ),
      isExpanded: true,
      itemHeight: null,
      selectedItemBuilder: (context) => categories
          .map(
            (cat) => Text(
              cat['label']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppConstants.onSurface,
              ),
            ),
          )
          .toList(),
      decoration: InputDecoration(
        hintText: 'Select a category',
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppConstants.outline.withValues(alpha: 0.50),
        ),
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(
          Icons.category_outlined,
          size: 20,
          color: AppConstants.outline,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(
            color: AppConstants.primaryContainer,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      items: categories
          .map(
            (cat) => DropdownMenuItem<String>(
              value: cat['value'],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cat['label']!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cat['example']!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppConstants.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
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
          color: AppConstants.errorRed.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppConstants.errorRed,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.errorRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Smart Suggestion Card
// ─────────────────────────────────────────────────────────────────────────────

class _SmartSuggestionCard extends StatelessWidget {
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
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppConstants.onPrimaryContainer.withValues(
                    alpha: 0.20,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: AppConstants.primaryGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart Suggestion',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppConstants.charcoal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Detailed categorization helps in accurate analytics and market matching.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppConstants.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Action Bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  final Animation<double> shakeAnimation;
  final AnimationController shakeController;
  final bool isLoading;
  final bool isSuccess;
  final VoidCallback onPressed;

  const _BottomActionBar({
    required this.shakeAnimation,
    required this.shakeController,
    required this.isLoading,
    required this.isSuccess,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
            ),
          ),
          child: AnimatedBuilder(
            animation: shakeAnimation,
            builder: (_, child) => Transform.translate(
              offset: Offset(shakeAnimation.value, 0),
              child: child,
            ),
            child: _CreateButton(
              isLoading: isLoading,
              isSuccess: isSuccess,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  final bool isLoading;
  final bool isSuccess;
  final VoidCallback onPressed;

  const _CreateButton({
    required this.isLoading,
    required this.isSuccess,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSuccess
                ? [AppConstants.successGreen, AppConstants.successGreen]
                : [AppConstants.primaryContainer, AppConstants.midGreen],
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          boxShadow: [
            BoxShadow(
              color: AppConstants.primaryGreen.withValues(alpha: 0.20),
              blurRadius: 16,
              offset: const Offset(0, 6),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else if (isSuccess)
                const Icon(
                  Icons.done_all_rounded,
                  size: 22,
                  color: Colors.white,
                )
              else
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              const SizedBox(width: 10),
              Text(
                isLoading
                    ? 'Processing...'
                    : isSuccess
                    ? 'Crop Added!'
                    : 'Create',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
